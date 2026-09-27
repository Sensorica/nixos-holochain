# Checks on what holochain-conductor-exporter writes, run on captured replies
# with no conductor: one edgenode-shaped conductor (Workshop, the homelab's
# Holochain 0.6.3 conductor with three apps, tests/fixtures/edgenode-0_6_3) and
# one Moss-shaped conductor (a Moss group node with two chats, Holochain 0.6.1,
# tests/fixtures/dht-0_6_1), each through the whole program, with an `hc` that
# answers from those files.
#
# The arguments other than pkgs and exporter exist so a deliberately broken
# input can be fed through the same checks and seen to fail; the flake passes
# none of them.
{
  pkgs,
  # packages/holochain-conductor-exporter.nix, as callPackage returns it.
  exporter,
  # The families table the Moss-shaped conductor's exporter is built with, as
  # if the two conductors on one machine ran two versions of the program.
  mossFamilies ? ../modules/families.jq,
  # Merged over the Moss names file below.
  extraMossNames ? {},
}: let
  # An `hc` that answers each admin call from $FAKE_HC_DIR/<call>.json and
  # logs its arguments to $FAKE_HC_DIR/calls. Its version is what picks the
  # admin call the program makes, so each side gets the line it runs on.
  fakeHc = version:
    (pkgs.writeShellScriptBin "hc" ''
      echo "$*" >> "$FAKE_HC_DIR/calls"
      for arg in "$@"; do
        case "$arg" in
          list-apps | dump-network-stats | dump-network-metrics)
            exec cat "$FAKE_HC_DIR/$arg.json"
            ;;
        esac
      done
      exit 1
    '')
    // {inherit version;};

  workshopExporter = exporter.override {hc = fakeHc "0.7.0";};
  mossExporter = exporter.override {
    hc = fakeHc "0.6.1";
    families = mossFamilies;
  };

  # A fixed admin port for the edgenode; a port and an origin for Moss, which
  # picks both at every start.
  workshopAdmin = pkgs.writeShellScript "workshop-admin" "echo 4444";
  mossAdmin = pkgs.writeShellScript "moss-admin" "echo 40123 moss-7f3a";

  # What the edgenode module writes for the homelab's apps.
  workshopNames = pkgs.writeText "workshop-names.json" (builtins.toJSON {
    apps.requests-and-offers = {
      name = "Requests & Offers";
      roles = {
        requests_and_offers = "Listings";
        hrea = "Accounting";
      };
    };
    kinds = {};
    expected = ["hrea" "kando" "requests-and-offers"];
  });

  # What a Moss wrapper would write: the group's name, one chat's name typed
  # in Nix, and a part table per tool kind. The other chat is left unnamed on
  # purpose, to take the fallback.
  mossNames = pkgs.writeText "moss-names.json" (builtins.toJSON (pkgs.lib.recursiveUpdate {
      apps = {
        "group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null".name = "Sensorica";
        "applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$".name = "General chat";
      };
      kinds = {
        Vines = {
          rVines = "Messages";
          rFiles = "Files";
        };
        Group = {
          group = "Members and tools";
          foyer = "Foyer";
          assets = "Shared assets";
        };
      };
      expected = [];
    }
    extraMossNames));

  # Byte and message counts on two live connections; the program needs a
  # dump-network-stats reply to report the conductor up.
  stats = pkgs.writeText "dump-network-stats.json" (builtins.toJSON {
    transport_stats = {
      backend = "iroh";
      peer_urls = ["u1"];
      connections = [
        {
          pub_key = "a";
          send_message_count = 3;
          send_bytes = 100;
          recv_message_count = 4;
          recv_bytes = 200;
          opened_at_s = 1;
          is_direct = true;
        }
      ];
    };
    blocked_message_counts = {};
  });

  # One run of each conductor, and the Moss one again with no names file at
  # all, which is what a Moss node shows before anyone types a name.
  runs =
    pkgs.runCommand "holochain-exporter-fixture-runs" {
      nativeBuildInputs = [pkgs.prometheus.cli];
    } ''
      mkdir workshop moss state-workshop state-moss state-bare
      cp ${../tests/fixtures/edgenode-0_6_3/list-apps.json} workshop/list-apps.json
      cp ${../tests/fixtures/edgenode-0_6_3/dump-network-metrics.json} workshop/dump-network-metrics.json
      cp ${../tests/fixtures/dht-0_6_1/list-apps.json} moss/list-apps.json
      cp ${../tests/fixtures/dht-0_6_1/dump-network-metrics.json} moss/dump-network-metrics.json
      cp ${stats} workshop/dump-network-stats.json
      cp ${stats} moss/dump-network-stats.json

      FAKE_HC_DIR=$PWD/workshop ${pkgs.lib.getExe workshopExporter} --conductor Workshop \
        --admin ${workshopAdmin} --names ${workshopNames} --out $PWD/holochain-conductor.prom --state-dir state-workshop
      FAKE_HC_DIR=$PWD/moss ${pkgs.lib.getExe mossExporter} --conductor Moss \
        --admin ${mossAdmin} --names ${mossNames} --out $PWD/moss-node.prom --state-dir state-moss
      : > moss/calls
      FAKE_HC_DIR=$PWD/moss ${pkgs.lib.getExe mossExporter} --conductor Moss \
        --admin ${mossAdmin} --out $PWD/moss-bare.prom --state-dir state-bare

      for f in holochain-conductor.prom moss-node.prom moss-bare.prom; do
        echo "==== $f"
        cat $f
        promtool check metrics < $f
      done

      # The admin call each line needs, with the origin only where one was given.
      echo "==== hc calls"
      cat workshop/calls moss/calls
      grep -qx 'client call --port 4444 list-apps' workshop/calls
      grep -qx 'sandbox call --running 40123 --origin moss-7f3a list-apps' moss/calls
      grep -qx 'sandbox call --running 40123 --origin moss-7f3a dump-network-metrics --include-dht-summary' moss/calls

      # Both conductors up, and every DHT of each fixture reported: four on
      # Workshop, seven on Moss.
      grep -qx 'holochain_conductor_up{conductor="Workshop"} 1' holochain-conductor.prom
      grep -qx 'holochain_conductor_up{conductor="Moss"} 1' moss-node.prom
      test "$(grep -c '^holochain_dht_peers{' holochain-conductor.prom)" = 4
      test "$(grep -c '^holochain_dht_peers{' moss-node.prom)" = 7
      test "$(grep -c '^holochain_dht_info{' moss-bare.prom)" = 7

      mkdir $out
      cp holochain-conductor.prom moss-node.prom moss-bare.prom $out/
    '';
in {
  # node_exporter merges the textfiles of one directory by family, and drops a
  # family from the second file when the two disagree on its HELP text. So
  # every HELP and TYPE line of a family the two conductors share must be
  # byte-identical, and a real node_exporter reading both files must keep
  # every series of both, with no scrape error.
  metricsHelpAgreement =
    pkgs.runCommand "metrics-help-agreement" {
      nativeBuildInputs = [pkgs.jq pkgs.curl pkgs.prometheus-node-exporter];
    } ''
      # {family: ["HELP ...", "TYPE ..."]} for one file.
      decl() {
        jq -R -s '[split("\n")[] | capture("^# (?<kind>HELP|TYPE) (?<name>[^ ]+)(?<text>.*)$")]
          | group_by(.name) | map({key: .[0].name, value: map(.kind + .text)}) | from_entries' "$1"
      }
      decl ${runs}/holochain-conductor.prom > workshop.json
      decl ${runs}/moss-node.prom > moss.json

      jq -n --slurpfile a workshop.json --slurpfile b moss.json '
        $a[0] as $a | $b[0] as $b
        | [$a | keys[] | select($b[.] != null)] as $shared
        | ($shared | length) as $n
        | [$shared[] | select($a[.] != $b[.]) | {family: ., workshop: $a[.], moss: $b[.]}] as $differ
        | [["holochain_conductor_up", "holochain_conductor_apps", "holochain_app_info",
            "holochain_dht_info", "holochain_dht_peers"][] | select(IN($shared[]) | not)] as $absent
        | if $differ != [] then error("HELP or TYPE differs between the two conductors: \($differ)")
          elif $absent != [] then error("families the comparison needs are not in both files: \($absent)")
          elif ([$a[], $b[]] | any(length != 2)) then error("a family is declared more than once in one file")
          else "\($n) families in both files, declared identically" end'

      # The same two files, as node_exporter sees them on the homelab, where
      # holochain-conductor.prom sorts first.
      mkdir textfiles
      cp ${runs}/holochain-conductor.prom ${runs}/moss-node.prom textfiles/
      node_exporter --collector.disable-defaults --collector.textfile \
        --collector.textfile.directory=textfiles --web.listen-address=127.0.0.1:19100 2> node_exporter.log &
      pid=$!
      for _ in $(seq 1 100); do
        if curl -sf http://127.0.0.1:19100/metrics > scraped; then break; fi
        sleep 0.1
      done
      kill $pid
      cat node_exporter.log
      grep '^node_textfile_scrape_error' scraped
      grep -qx 'node_textfile_scrape_error 0' scraped
      if grep -q 'inconsistent metric help text' node_exporter.log; then
        echo "node_exporter found HELP texts that disagree" >&2
        exit 1
      fi
      for conductor in Workshop:4 Moss:7; do
        name=''${conductor%:*}
        want=''${conductor#*:}
        got=$(grep -c "^holochain_dht_peers{.*conductor=\"$name\"" scraped || true)
        test "$got" = "$want" || { echo "node_exporter kept $got of $want holochain_dht_peers series for $name" >&2; exit 1; }
        grep -q "^holochain_conductor_up{conductor=\"$name\"} 1" scraped
        grep -q "^holochain_dht_info{.*conductor=\"$name\"" scraped
      done
      touch $out
    '';

  # No name a dashboard shows may be a machine key: no Moss `$` case escape,
  # no hash (uhC...), and no long run of id characters without a space.
  metricsNameShape =
    pkgs.runCommand "metrics-name-shape" {
      nativeBuildInputs = [pkgs.jq];
    } ''
      for f in holochain-conductor.prom moss-node.prom moss-bare.prom; do
        jq -R -s --arg file "$f" '
          [split("\n")[]
            | scan("(app_name|app_kind|part_name|network_label)=\"((?:[^\"\\\\]|\\\\.)*)\"")
            | {label: .[0], value: .[1]}] as $names
          | [$names[] | select(.value | test("\\$") or startswith("uhC") or test("^[A-Za-z0-9_-]{20,}$"))] as $bad
          | if ($names | length) == 0 then error("\($file): no name labels at all")
            elif $bad != [] then error("\($file): names that are machine keys: \($bad | unique)")
            else "\($file): \($names | length) name labels, none of them a key" end' ${runs}/$f
      done
      touch $out
    '';

  inherit runs;
}
