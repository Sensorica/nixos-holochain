# Called from nix/checks.nix with the per-system arguments of
# nix/shared.nix.
# The per-DHT jq against replies captured from two real conductors:
# a Holochain 0.6.1 Moss group node in seven DHTs and the homelab's
# 0.6.3 edgenode conductor with three apps in four (both 2026-09-27;
# network seeds redacted, nothing the jq reads changed), against the
# ways the calls fail, against names files good and bad, and against
# label values that would break the textfile if they reached it
# unescaped. Every output goes through promtool, alone and appended
# to the conductor series as the exporter writes it.
{
  jqLib,
  pkgs,
  ...
}:
pkgs.runCommand "dht-metrics-jq" {
  nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli];
} ''
  apps=${./fixtures/dht-0_6_1/list-apps.json}
  metrics=${./fixtures/dht-0_6_1/dump-network-metrics.json}
  ws_apps=${./fixtures/edgenode-0_6_3/list-apps.json}
  ws_metrics=${./fixtures/edgenode-0_6_3/dump-network-metrics.json}

  # The three documents on stdin, list-apps first and the names
  # file last, as the exporter passes them; the conductor is Moss
  # unless a fourth argument names another.
  dht() {
    printf '%s\n%s\n%s\n' "$1" "$2" "''${3:-null}" \
      | jq -n -r -L ${jqLib} --arg conductor "''${4:-Moss}" --argjson now 1790484800 \
          -f ${jqLib}/dht-metrics.jq
  }

  # No two apps of one conductor share an app_name, and no two of
  # its DHTs share a network_label, or a dashboard would draw two
  # things under one name.
  names_unique() {
    { grep '^holochain_app_info{' "$1" || true; } \
      | sed -E 's/^holochain_app_info\{conductor="((\\.|[^"\\])*)",app_id="((\\.|[^"\\])*)",app_name="((\\.|[^"\\])*)",.*/\1 \5/' \
      | sort > app.names
    { grep '^holochain_dht_info{' "$1" || true; } \
      | sed -E 's/^holochain_dht_info\{conductor="((\\.|[^"\\])*)",.*,network_label="((\\.|[^"\\])*)"\} 1$/\1 \3/' \
      | sort > network.names
    for f in app.names network.names; do
      if [ -n "$(uniq -d $f)" ]; then
        echo "$1: names shared by two of one conductor's items in $f:" >&2
        uniq -d $f >&2
        exit 1
      fi
    done
  }

  # Every data series has exactly one info row with the same key,
  # and the other way round; then the names are distinct.
  keys_match() {
    grep '^holochain_dht_peers{' "$1" | sed -E 's/^holochain_dht_peers\{(.*)\} [-0-9]+$/\1/' | sort > data.keys
    grep '^holochain_dht_info{' "$1" \
      | sed -E 's/^holochain_dht_info\{(conductor="[^"]*",app_id="[^"]*",role="[^"]*",dna="[^"]*"),.*/\1/' | sort > info.keys
    diff data.keys info.keys
    test "$(sort -u info.keys | wc -l)" = "$(wc -l < info.keys)"
    names_unique "$1"
  }

  dht "$(cat $apps)" "$(cat $metrics)" > out.prom
  cat out.prom
  promtool check metrics < out.prom

  # Seven DHTs, seven series of each metric, one name row each.
  for name in peers local_ops peer_ops pending_fetches seconds_since_gossip \
    completed_rounds_total peer_timeouts_total info; do
    n=$(grep -c "^holochain_dht_$name{" out.prom)
    test "$n" = 7 || { echo "holochain_dht_$name: $n series, expected 7" >&2; exit 1; }
  done
  keys_match out.prom
  # Data series carry machine keys only; `app` became app_id.
  if grep -E '^holochain_dht_[a-z_]+\{' out.prom | grep -v '^holochain_dht_info' \
    | grep -E '[{,](app|app_name|app_kind|part_name|network_label)="'; then
    echo "a data series carries a name label" >&2
    exit 1
  fi

  # The group DHT, read by hand from the fixture: one peer holding
  # 975 ops against 948 here, 61 rounds, last gossip at
  # 1790484723.53 s, so 76.47 s before the fixed now, floored.
  group='conductor="Moss",app_id="group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null",role="group",dna="uhC0kDTZE5JwUHP9yIz2Bhjq2TPdkLSNhJtqTdq5RzS7vFPfrIvJY"'
  grep -qxF "holochain_dht_peers{$group} 1" out.prom
  grep -qxF "holochain_dht_local_ops{$group} 948" out.prom
  grep -qxF "holochain_dht_peer_ops{$group} 975" out.prom
  grep -qxF "holochain_dht_pending_fetches{$group} 0" out.prom
  grep -qxF "holochain_dht_completed_rounds_total{$group} 61" out.prom
  grep -qxF "holochain_dht_peer_timeouts_total{$group} 0" out.prom
  grep -qxF "holochain_dht_seconds_since_gossip{$group} 76" out.prom

  # Two applets of one tool share role names; the app_id label keeps
  # them apart. The second has never gossiped: -1, not a huge age.
  grep -c '^holochain_dht_peers{.*role="rVines"' out.prom | grep -qx 2
  grep '^holochain_dht_seconds_since_gossip{' out.prom | grep -F k1h2cpht | grep -F 'role="rVines"' | grep -q ' -1$'

  # With no names file, Moss names come from the bundles: the two
  # chats of one tool are numbered in installed_app_id order, the
  # group is Group, and a role reads as its id without its prefix,
  # or as Main where that would only repeat the app's kind.
  grep -qxF 'holochain_dht_info{conductor="Moss",app_id="applet#uhc$e$k1h2cpht$kfgs$v$l$t$3zhz-b$d_b$t$5kq$lyybe$vs$6lb$xzzsgd$hu$5ry$",role="rFiles",dna="uhC0kujTsC4x0m_WoAtP-Ct0WJtsAK8cK-UAOsIgvY0q30XjbFbRj",app_name="Vines 1",app_kind="Vines",part_name="Files",network_label="Vines 1: Files"} 1' out.prom
  grep -qF 'app_name="Vines 1",app_kind="Vines",part_name="Main",network_label="Vines 1: Main"} 1' out.prom
  grep -qxF 'holochain_app_info{conductor="Moss",app_id="applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$",app_name="Vines 2",app_kind="Vines",status="enabled"} 1' out.prom
  grep -qxF "holochain_dht_info{$group,app_name=\"Group\",app_kind=\"Group\",part_name=\"Main\",network_label=\"Group: Main\"} 1" out.prom
  test "$(grep -c '^holochain_app_info{' out.prom)" = 3

  # A Moss names file: the group's name, one chat's name, a part
  # table per kind. The unnamed chat keeps its number.
  cat > moss-names.json <<'EOF'
  {"apps":{"group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null":{"name":"Sensorica"},
           "applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$":{"name":"General chat"}},
   "kinds":{"Vines":{"rVines":"Messages","rFiles":"Files"},
            "Group":{"group":"Members and tools","foyer":"Foyer","assets":"Shared assets"}}}
  EOF
  dht "$(cat $apps)" "$(cat $metrics)" "$(cat moss-names.json)" > named.prom
  cat named.prom
  promtool check metrics < named.prom
  keys_match named.prom
  grep -qxF "holochain_dht_info{$group,app_name=\"Sensorica\",app_kind=\"Group\",part_name=\"Members and tools\",network_label=\"Sensorica: Members and tools\"} 1" named.prom
  grep -qxF 'holochain_dht_info{conductor="Moss",app_id="applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$",role="rVines",dna="uhC0kjGGg7aTaaHUDdSQgoqNAGekaa9rYCe0DjK6RwDr5KaaRaZeD",app_name="General chat",app_kind="Vines",part_name="Messages",network_label="General chat: Messages"} 1' named.prom
  grep -qF 'app_name="Vines 1",app_kind="Vines",part_name="Messages",network_label="Vines 1: Messages"} 1' named.prom
  # Names never touch the data series.
  grep -v '_info' out.prom > out.data
  grep -v '_info' named.prom > named.data
  diff out.data named.data

  # The Moss conductor stopped: the wrapper's names file still
  # lists every app it has seen as expected, one of them with its
  # kind. Nothing is named after its id, a group is still a Group,
  # and a tool is its given kind, else Tool, numbered like the
  # chats above.
  G='group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null'
  A1='applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$'
  A2='applet#uhc$e$k1h2cpht$kfgs$v$l$t$3zhz-b$d_b$t$5kq$lyybe$vs$6lb$xzzsgd$hu$5ry$'
  jq --arg g "$G" --arg a1 "$A1" --arg a2 "$A2" \
    '.expected = [$g, $a1, $a2] | .apps[$a1].kind = "Vines"' moss-names.json > moss-seen.json
  dht null null "$(cat moss-seen.json)" > moss-down.prom
  cat moss-down.prom
  promtool check metrics < moss-down.prom
  names_unique moss-down.prom
  grep -qxF "holochain_app_info{conductor=\"Moss\",app_id=\"$G\",app_name=\"Sensorica\",app_kind=\"Group\",status=\"expected\"} 1" moss-down.prom
  grep -qxF "holochain_app_info{conductor=\"Moss\",app_id=\"$A1\",app_name=\"General chat\",app_kind=\"Vines\",status=\"expected\"} 1" moss-down.prom
  grep -qxF "holochain_app_info{conductor=\"Moss\",app_id=\"$A2\",app_name=\"Tool\",app_kind=\"Tool\",status=\"expected\"} 1" moss-down.prom
  jq '.expected = [.apps | keys[]] + ["applet#uhc$x", "applet#uhc$y"] | del(.apps[].name)' moss-seen.json > moss-bare-seen.json
  dht null null "$(cat moss-bare-seen.json)" > moss-bare-down.prom
  cat moss-bare-down.prom
  names_unique moss-bare-down.prom
  grep -qF 'app_id="group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null",app_name="Group",app_kind="Group",status="expected"' moss-bare-down.prom
  grep -qF 'app_id="applet#uhc$x",app_name="Tool 1",app_kind="Tool",status="expected"' moss-bare-down.prom
  grep -qF 'app_id="applet#uhc$y",app_name="Tool 2",app_kind="Tool",status="expected"' moss-bare-down.prom
  if grep -F 'app_name="' moss-down.prom moss-bare-down.prom | grep -E 'app_(name|kind)="[^"]*[$#]'; then
    echo "an expected Moss app is named after its id" >&2
    exit 1
  fi

  # A given name can match another app's fallback, or another given
  # name. Each app still gets a name of its own, the given one kept
  # where it can be.
  cat > clash-apps.json <<'EOF'
  [{"installed_app_id":"x","status":{"type":"enabled"},"manifest":{"name":"kando"},"cell_info":{}},
   {"installed_app_id":"y","status":{"type":"enabled"},"manifest":{"name":"board"},"cell_info":{}},
   {"installed_app_id":"p","status":{"type":"enabled"},"manifest":{"name":"p"},"cell_info":{}},
   {"installed_app_id":"q","status":{"type":"enabled"},"manifest":{"name":"q"},"cell_info":{}}]
  EOF
  dht "$(cat clash-apps.json)" '{}' '{"apps":{"y":{"name":"Kando"},"p":{"name":"Chat"},"q":{"name":"Chat"}}}' W > clash.prom
  cat clash.prom
  names_unique clash.prom
  grep -qxF 'holochain_app_info{conductor="W",app_id="y",app_name="Kando",app_kind="Kando",status="enabled"} 1' clash.prom
  grep -qxF 'holochain_app_info{conductor="W",app_id="x",app_name="Kando 2",app_kind="Kando 2",status="enabled"} 1' clash.prom
  grep -qxF 'holochain_app_info{conductor="W",app_id="p",app_name="Chat",app_kind="Chat",status="enabled"} 1' clash.prom
  grep -qxF 'holochain_app_info{conductor="W",app_id="q",app_name="Chat 2",app_kind="Chat 2",status="enabled"} 1' clash.prom

  # The edgenode shape, with a names file typed in the shape the
  # module writes (checks.edgenodeNamesWiring runs the module's
  # own): a display name and role names for one app, the bundle's
  # name for the others, and a one-role app's network named by the
  # app alone.
  cat > ws-names.json <<'EOF'
  {"apps":{"requests-and-offers":{"name":"Requests & Offers",
             "roles":{"requests_and_offers":"Listings","hrea":"Accounting"}}},
   "kinds":{},"expected":["hrea","kando","requests-and-offers","not-installed"]}
  EOF
  dht "$(cat $ws_apps)" "$(cat $ws_metrics)" "$(cat ws-names.json)" Workshop > ws.prom
  cat ws.prom
  promtool check metrics < ws.prom
  keys_match ws.prom
  test "$(grep -c '^holochain_dht_info{' ws.prom)" = 4
  grep -qxF 'holochain_dht_info{conductor="Workshop",app_id="requests-and-offers",role="requests_and_offers",dna="uhC0k5Kg49j1kwUFmDlTqLBXoQAZHQdutkEojX0m_OKSqBtERwBOY",app_name="Requests & Offers",app_kind="Requests & Offers",part_name="Listings",network_label="Requests & Offers: Listings"} 1' ws.prom
  grep -qxF 'holochain_dht_info{conductor="Workshop",app_id="kando",role="kando",dna="uhC0kFujhaUaX5mZCE1BbC-ZtzLJMNr3-wyIDKd4N1Tn6Avrfk8cD",app_name="Kando",app_kind="Kando",part_name="",network_label="Kando"} 1' ws.prom
  grep -qxF 'holochain_app_info{conductor="Workshop",app_id="hrea",app_name="Hrea",app_kind="Hrea",status="enabled"} 1' ws.prom
  grep -qxF 'holochain_app_info{conductor="Workshop",app_id="requests-and-offers",app_name="Requests & Offers",app_kind="Requests & Offers",status="enabled"} 1' ws.prom
  # Expected by Nix and not listed: there, and not running.
  grep -qxF 'holochain_app_info{conductor="Workshop",app_id="not-installed",app_name="Not installed",app_kind="Not installed",status="expected"} 1' ws.prom
  test "$(grep -c '^holochain_app_info{' ws.prom)" = 4

  # list-apps did not answer: every app Nix expects is written as
  # expected, and nothing else is.
  dht null "$(cat $ws_metrics)" "$(cat ws-names.json)" Workshop > down.prom
  cat down.prom
  promtool check metrics < down.prom
  grep -qxF 'holochain_app_info{conductor="Workshop",app_id="requests-and-offers",app_name="Requests & Offers",app_kind="Requests & Offers",status="expected"} 1' down.prom
  grep -qxF 'holochain_app_info{conductor="Workshop",app_id="kando",app_name="Kando",app_kind="Kando",status="expected"} 1' down.prom
  test "$(grep -c '^holochain_app_info{' down.prom)" = 4
  test "$(grep -c -v '^#\|^holochain_app_info{' down.prom)" = 0

  # A names file of the wrong shape costs the names, not the series.
  for bad in '[]' '"x"' '{"apps":[],"kinds":"x","expected":"x"}' \
    '{"apps":{"kando":"Kando"}}' '{"apps":{"kando":{"name":7,"roles":["x"]}}}'; do
    dht "$(cat $ws_apps)" "$(cat $ws_metrics)" "$bad" Workshop > bad.prom
    promtool check metrics < bad.prom
    test "$(grep -c '^holochain_dht_peers{' bad.prom)" = 4
    grep -qF 'app_id="kando",role="kando",dna="uhC0kFujhaUaX5mZCE1BbC-ZtzLJMNr3-wyIDKd4N1Tn6Avrfk8cD",app_name="Kando"' bad.prom
  done

  # A failed call writes no DHT series rather than zeros; list-apps
  # alone still names the apps.
  dht null "$(cat $metrics)" > failed.prom
  dht "$(cat $apps)" null >> failed.prom
  dht null null >> failed.prom
  dht "$(cat $apps)" '{}' >> failed.prom
  dht '[]' "$(cat $metrics)" >> failed.prom
  if grep -q '^holochain_dht_' failed.prom; then
    echo "per-DHT series without both replies" >&2
    exit 1
  fi
  test -z "$(dht null null)"
  test -z "$(dht '[]' "$(cat $metrics)")"
  test "$(dht "$(cat $apps)" null | grep -c '^holochain_app_info{')" = 3

  # Hostile and malformed input: a quote, a backslash and a newline
  # in an app id and in the conductor name, a stem cell without a
  # cell_id, two cloned cells (one with a clone_id, one without), a
  # DNA the reply does not mention, and fields of the wrong type.
  cat > odd-apps.json <<'EOF'
  [{"installed_app_id":"we\"ird\\app\nid","status":{"type":"enabled"},
    "cell_info":{"main":[
      {"type":"provisioned","value":{"cell_id":{"dna_hash":"dnaA","agent_pub_key":"k"}}},
      {"type":"cloned","value":{"clone_id":"main.2","cell_id":{"dna_hash":"dnaB","agent_pub_key":"k"}}},
      {"type":"cloned","value":{"cell_id":{"dna_hash":"dnaE","agent_pub_key":"k"}}},
      {"type":"stem","value":{"original_dna_hash":"dnaC"}}],
     "gone":[{"type":"provisioned","value":{"cell_id":{"dna_hash":"dnaD","agent_pub_key":"k"}}}]}}]
  EOF
  cat > odd-metrics.json <<'EOF'
  {"dnaA":{"fetch_state_summary":{"pending_requests":{"op1":["u"],"op2":["u"]}},
           "gossip_state_summary":{"peer_meta":{
             "u1":{"last_gossip_timestamp":1790484790000000,"completed_rounds":2,"peer_timeouts":1,"dht_op_count":10},
             "u2":{"last_gossip_timestamp":null,"completed_rounds":"x","peer_timeouts":null,"dht_op_count":12}},
             "local_op_count":11}},
   "dnaB":{"fetch_state_summary":null,"gossip_state_summary":{"peer_meta":null,"local_op_count":null}},
   "dnaE":{}}
  EOF
  dht "$(cat odd-apps.json)" "$(cat odd-metrics.json)" null "$(printf 'M"o\\\ns')" > odd.prom
  cat odd.prom
  promtool check metrics < odd.prom
  key='conductor="M\"o\\\ns",app_id="we\"ird\\app\nid",role="main"'
  test "$(grep -c '^holochain_dht_peers{' odd.prom)" = 3
  # The clones share conductor, app_id and role with the cell they
  # came from, so each gets a name of its own: the clone index plus
  # one from its clone_id, else its place among the role's clones.
  names_unique odd.prom
  for want in 'dnaA:Main' 'dnaB:Main (clone 3)' 'dnaE:Main (clone 2)'; do
    grep -F "holochain_dht_info{$key,dna=\"''${want%%:*}\"," odd.prom | grep -qF "part_name=\"''${want#*:}\","
  done
  grep -qF "holochain_dht_peers{$key,dna=\"dnaA\"} 2" odd.prom
  grep -qF "holochain_dht_pending_fetches{$key,dna=\"dnaA\"} 2" odd.prom
  grep -qF "holochain_dht_peer_ops{$key,dna=\"dnaA\"} 12" odd.prom
  grep -qF "holochain_dht_seconds_since_gossip{$key,dna=\"dnaA\"} 10" odd.prom
  grep -qF "holochain_dht_completed_rounds_total{$key,dna=\"dnaA\"} 2" odd.prom
  grep -qF "holochain_dht_seconds_since_gossip{$key,dna=\"dnaB\"} -1" odd.prom
  # The escaped app id reaches the names too, prettified.
  grep -qF 'holochain_app_info{conductor="M\"o\\\ns",app_id="we\"ird\\app\nid",app_name="We\"ird\\app\nid"' odd.prom
  if grep -q 'dnaC\|dnaD' odd.prom; then
    echo "a stem cell or a DNA outside the reply got series" >&2
    exit 1
  fi

  # The file as the exporter writes it: conductor series, then the
  # names and the DHT series, for each shape.
  for f in out.prom named.prom ws.prom; do
    echo '{}' | jq -r -L ${jqLib} --arg conductor Moss --argjson up 1 --argjson now 1790484800 --argjson totals '{}' \
      --argjson apps '[{"status":{"type":"enabled"}}]' -f ${jqLib}/conductor-metrics.jq > whole.prom
    cat $f >> whole.prom
    promtool check metrics < whole.prom
  done
  touch $out
''
