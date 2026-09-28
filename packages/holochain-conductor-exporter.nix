# The one program that writes holochain_* series for node_exporter's textfile
# collector, for any conductor: the edgenode module runs it for its own, and a
# Moss node (or any other conductor on the machine) runs it under its own name.
#
# One program, because node_exporter merges every *.prom file in its directory
# by family and drops a family's series from the second file when two files
# disagree on its HELP text (see modules/families.jq). Two exporters with their
# own HELP strings on one machine lose one conductor's series outright.
#
#   holochain-conductor-exporter --conductor NAME --admin COMMAND \
#     --out FILE --state-dir DIR [--names FILE]
#
# --conductor  the `conductor` label on every line it writes.
# --admin      an executable that prints the admin port, then optionally the
#              allowed origin, on one line. A command rather than a number
#              because a Moss node picks a new port and origin at every start;
#              an edgenode passes a script that echoes its fixed port. When it
#              prints nothing usable the conductor reads as down.
# --out        the textfile to replace. Written beside itself and moved into
#              place, so the collector never reads half a file.
# --state-dir  where the running byte and message totals live between runs
#              (conductor-metrics-counters.json, see conductor-counters.jq).
# --names      the names file dht-metrics.jq reads (apps, kinds, expected).
#
# `hc` selects the admin call: `hc client call --port` from 0.7, `hc sandbox
# call --running` below it. Override it to match the conductor's line:
#   holochain-conductor-exporter.override { hc = <an hc of that line>; }
{
  lib,
  runCommand,
  writeShellApplication,
  coreutils,
  jq,
  hc,
  # The HELP and TYPE table. Overridden only by checks.metricsHelpAgreement,
  # to show that two exporters built from different tables are caught.
  families ? ../modules/families.jq,
}: let
  isPre07 = lib.versionOlder hc.version "0.7";

  callPrefix =
    if isPre07
    then "sandbox call --running"
    else "client call --port";

  # The jq programs as one directory, which `jq -L` needs to resolve
  # `include "families";`.
  jqLib = runCommand "holochain-conductor-exporter-jq" {} ''
    mkdir -p $out
    cp ${families} $out/families.jq
    cp ${../modules/conductor-counters.jq} $out/conductor-counters.jq
    cp ${../modules/conductor-metrics.jq} $out/conductor-metrics.jq
    cp ${../modules/dht-metrics.jq} $out/dht-metrics.jq
  '';
in
  (writeShellApplication {
    name = "holochain-conductor-exporter";
    runtimeInputs = [hc coreutils jq];
    text = ''
      usage() {
        echo "usage: holochain-conductor-exporter --conductor NAME --admin COMMAND --out FILE --state-dir DIR [--names FILE]" >&2
        exit 2
      }

      conductor="" admin="" out="" state_dir="" names=""
      while [ "$#" -gt 0 ]; do
        [ "$#" -ge 2 ] || usage
        case "$1" in
          --conductor) conductor=$2 ;;
          --admin) admin=$2 ;;
          --out) out=$2 ;;
          --state-dir) state_dir=$2 ;;
          --names) names=$2 ;;
          *) usage ;;
        esac
        shift 2
      done
      if [ -z "$conductor" ] || [ -z "$admin" ] || [ -z "$out" ] || [ -z "$state_dir" ]; then
        usage
      fi

      # Port first, origin second, anything after ignored. A port that is not
      # a number leaves every call below failing, which is what a conductor
      # that is not there should look like.
      port="" origin=""
      endpoint=$("$admin" 2>/dev/null) || endpoint=""
      read -r port origin _ <<< "$endpoint" || true
      case "$port" in
        "" | *[!0-9]*) port="" ;;
      esac
      origin_args=()
      if [ -n "$origin" ]; then
        origin_args=(--origin "$origin")
      fi

      # 15 s is generous for a call over a loopback websocket; anything slower
      # is a conductor that is not well.
      call() {
        [ -n "$port" ] || return 1
        timeout 15 hc ${callPrefix} "$port" "''${origin_args[@]}" "$@" 2>/dev/null
      }

      # A conductor that is starting, restarting or wedged must not delete the
      # series: it reports holochain_conductor_up 0 and leaves every other
      # gauge at its zero value, which is what makes a dead node visible on the
      # dashboard rather than absent from it.
      if stats=$(call dump-network-stats) && printf '%s' "$stats" | jq -e . > /dev/null 2>&1; then
        up=1
      else
        up=0
        stats='{}'
      fi

      # null, not [], when the call fails: an unanswered list-apps must not
      # read as a conductor with no apps.
      if ! { apps=$(call list-apps) && printf '%s' "$apps" | jq -e 'type == "array"' > /dev/null 2>&1; }; then
        apps=null
      fi
      # The reply carries every DNA's properties and reaches jq below as one
      # command-line argument, which Linux caps at 128 KiB (MAX_ARG_STRLEN):
      # a Moss node with three apps already answers 110 KB. Only the status
      # is read from it there.
      app_status=$(printf '%s' "$apps" | jq -c 'if type == "array" then [.[] | {status: {type: .status.type}}] else . end')

      # Gossip and fetch state for every DHT the conductor is in, keyed by DNA
      # hash; list-apps names the app and role each DNA belongs to. null when
      # the call fails, and dht-metrics.jq then writes no per-DHT series.
      if ! { dht=$(call dump-network-metrics --include-dht-summary) && printf '%s' "$dht" | jq -e 'type == "object"' > /dev/null 2>&1; }; then
        dht=null
      fi

      # A names file that is missing or not an object costs the names, never
      # the series: every app then falls back to its bundle's name.
      names_doc='{}'
      if [ -n "$names" ]; then
        if doc=$(jq -c 'if type == "object" then . else error("not an object") end' "$names" 2>/dev/null); then
          names_doc=$doc
        else
          echo "names file $names is missing or not a JSON object; using no names" >&2
        fi
      fi

      # The reply counts bytes and messages per open connection only, so the
      # running totals live here between runs (see conductor-counters.jq). A
      # missing or unreadable file starts them from zero, which Prometheus
      # reads as the counter reset it is.
      state="$state_dir/conductor-metrics-counters.json"
      prev=$(cat "$state" 2>/dev/null || true)
      if ! printf '%s' "$prev" | jq -e 'type == "object"' > /dev/null 2>&1; then
        prev='{}'
      fi
      counters=$(printf '%s' "$stats" | jq -c --argjson prev "$prev" -f ${jqLib}/conductor-counters.jq)
      printf '%s\n' "$counters" > "$state.tmp"
      mv -f "$state.tmp" "$state"

      tmp="$out.tmp"
      now=$(date +%s)
      printf '%s' "$stats" \
        | jq -r -L ${jqLib} --arg conductor "$conductor" --argjson up "$up" --argjson now "$now" \
            --argjson totals "$(printf '%s' "$counters" | jq -c .totals)" \
            --argjson apps "$app_status" \
            -f ${jqLib}/conductor-metrics.jq > "$tmp"

      # Appended only when jq finished cleanly: a reply of a shape it did not
      # expect must cost the per-DHT and name series, never the conductor
      # series above or the file as a whole. The replies go through stdin
      # (see dht-metrics.jq for why not --argjson).
      if printf '%s\n%s\n%s\n' "$apps" "$dht" "$names_doc" \
        | jq -n -r -L ${jqLib} --arg conductor "$conductor" --argjson now "$now" \
            -f ${jqLib}/dht-metrics.jq > "$tmp.dht"; then
        cat "$tmp.dht" >> "$tmp"
      else
        echo "dht-metrics.jq failed; per-DHT and name series left out of this run" >&2
      fi
      rm -f "$tmp.dht"

      # node_exporter runs as its own user and must be able to read the file
      # whoever runs this. The collector may read the directory at any moment,
      # so the file is swapped in whole rather than truncated and rewritten.
      chmod 0644 "$tmp"
      mv -f "$tmp" "$out"
    '';
  })
  .overrideAttrs (old: {
    passthru = (old.passthru or {}) // {inherit jqLib;};
  })
