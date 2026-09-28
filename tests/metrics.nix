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
  # A Moss node that is not running has no port to print.
  mossDownAdmin = pkgs.writeShellScript "moss-down-admin" "true";

  # The shape the edgenode module writes for the homelab's apps, typed by
  # hand; checks.edgenodeNamesWiring runs the module's own.
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

  # What a Moss wrapper would write: the group's name, one chat's name and
  # kind typed in Nix, a part table per tool kind, and every app it has seen
  # as expected, so a stopped Moss conductor still reports them. The other
  # chat is left unnamed and without a kind on purpose, to take the fallbacks.
  mossNames = pkgs.writeText "moss-names.json" (builtins.toJSON (pkgs.lib.recursiveUpdate {
      apps = {
        "group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null".name = "Sensorica";
        "applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$" = {
          name = "General chat";
          kind = "Vines";
        };
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
      expected = [
        "group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null"
        "applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$"
        "applet#uhc$e$k1h2cpht$kfgs$v$l$t$3zhz-b$d_b$t$5kq$lyybe$vs$6lb$xzzsgd$hu$5ry$"
      ];
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

  # One run of each conductor, the Moss one again with no names file at all,
  # which is what a Moss node shows before anyone types a name, and once more
  # with the Moss conductor stopped, when only the names file knows its apps.
  runs =
    pkgs.runCommand "holochain-exporter-fixture-runs" {
      nativeBuildInputs = [pkgs.prometheus.cli];
    } ''
      mkdir workshop moss state-workshop state-moss state-bare state-down
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
      FAKE_HC_DIR=$PWD/moss ${pkgs.lib.getExe mossExporter} --conductor Moss \
        --admin ${mossDownAdmin} --names ${mossNames} --out $PWD/moss-down.prom --state-dir state-down

      for f in holochain-conductor.prom moss-node.prom moss-bare.prom moss-down.prom; do
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
      # Stopped: down, no DHT series, and each of the three apps still there.
      grep -qx 'holochain_conductor_up{conductor="Moss"} 0' moss-down.prom
      test "$(grep -c '^holochain_dht_' moss-down.prom || true)" = 0
      test "$(grep -c '^holochain_app_info{.*status="expected"} 1$' moss-down.prom)" = 3

      mkdir $out
      cp holochain-conductor.prom moss-node.prom moss-bare.prom moss-down.prom $out/
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
      # node_exporter also drops, with scrape_error still 0, a series another
      # file already gave with the same name and labels (two conductors under
      # one name, or a family that lost its conductor label). So every sample
      # line of the two files must come out, one for one.
      if grep -q 'was collected before with the same name and label values' node_exporter.log; then
        echo "node_exporter dropped a series it had already collected from another file" >&2
        exit 1
      fi
      written=$(cat textfiles/*.prom | grep -c '^holochain_')
      served=$(grep -c '^holochain_' scraped)
      echo "sample lines written: $written, served by node_exporter: $served"
      test "$written" = "$served" || { echo "node_exporter served $served of $written holochain_* samples" >&2; exit 1; }
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

  # No name a dashboard shows may be a machine key, or carry one anywhere in
  # it: no Moss `$` case escape, no hash (uhC...), and no run of twenty or more
  # id characters without a space, at the start, the end or in between.
  metricsNameShape =
    pkgs.runCommand "metrics-name-shape" {
      nativeBuildInputs = [pkgs.jq];
    } ''
      for f in holochain-conductor.prom moss-node.prom moss-bare.prom moss-down.prom; do
        jq -R -s --arg file "$f" '
          [split("\n")[]
            | scan("(app_name|app_kind|part_name|network_label)=\"((?:[^\"\\\\]|\\\\.)*)\"")
            | {label: .[0], value: .[1]}] as $names
          | [$names[] | select(.value | test("\\$") or test("uhC") or test("[A-Za-z0-9_-]{20,}"))] as $bad
          | if ($names | length) == 0 then error("\($file): no name labels at all")
            elif $bad != [] then error("\($file): names that are machine keys: \($bad | unique)")
            else "\($file): \($names | length) name labels, none of them a key" end' ${runs}/$f
      done
      touch $out
    '';

  # The fleet dashboard's conductor and DHT queries, run by promtool on what
  # the exporter writes when two conductors share one instance (the homelab's
  # shape), plus a clone cell, which shares conductor, app_id and role with the
  # cell it came from. The node's conductor state is its worst conductor's;
  # each DHT panel names its lines by network_label through a join that the
  # clone cannot make many-to-many; and no legend names a machine key or
  # leaves two conductors' lines under one name.
  fleetDashboardQueries =
    pkgs.runCommand "fleet-dashboard-queries" {
      nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli];
    } ''
      dashboard=${../modules/dashboards/holochain-fleet.json}

      # A third conductor with one app in two DHTs of one role, the second a
      # clone, through the same jq the exporter runs.
      printf '%s\n%s\n%s\n' \
        '[{"installed_app_id":"notes","status":{"type":"enabled"},"manifest":{"name":"notes"},"cell_info":{"main":[
           {"type":"provisioned","value":{"cell_id":{"dna_hash":"dnaA","agent_pub_key":"k"}}},
           {"type":"cloned","value":{"clone_id":"main.0","cell_id":{"dna_hash":"dnaB","agent_pub_key":"k"}}}]}}]' \
        '{"dnaA":{},"dnaB":{}}' null \
        | jq -n -r -L ${exporter.jqLib} --arg conductor Clones --argjson now 1790484800 \
            -f ${exporter.jqLib}/dht-metrics.jq > clones.prom
      cat clones.prom

      # promtool input series: every sample line of the files, on one
      # instance, held for the whole test.
      series() {
        cat "$@" | grep -v '^#' \
          | sed -E 's/^([a-z_]+)\{/\1{instance="home",/' \
          | jq -R '. as $l | capture("^(?<s>.*) (?<v>[^ ]+)$") | {series: .s, values: "\(.v)+0x10"}' \
          | jq -s .
      }
      series ${runs}/holochain-conductor.prom ${runs}/moss-down.prom > down.json
      series ${runs}/holochain-conductor.prom ${runs}/moss-node.prom clones.prom > dht.json

      target() {
        jq -r --arg title "$1" --arg ref "$2" '
          [.panels[] | ., (.panels // [])[] | select(.title == $title) | .targets[] | select(.refId == $ref) | .expr]
          | if length == 1 then .[0] | gsub("\\$instance"; ".*") else error("no single \($title) \($ref) target") end' $dashboard
      }

      # What the DHT peers panel must answer, computed here from the files:
      # for each network_label, the fewest peers of the DHTs its info rows
      # name.
      cat ${runs}/holochain-conductor.prom ${runs}/moss-node.prom clones.prom | grep -v '^#' \
        | jq -R -s '
            [split("\n")[] | select(. != "")
              | capture("^(?<name>[a-z_]+)\\{(?<labels>.*)\\} (?<value>[^ ]+)$")
              | .labels |= ([scan("([a-z_]+)=\"((?:[^\"\\\\]|\\\\.)*)\"") | {key: .[0], value: .[1]}] | from_entries)]
            | (map(select(.name == "holochain_dht_peers")
                   | {key: ([.labels.conductor, .labels.app_id, .labels.role, .labels.dna] | tostring), value: (.value | tonumber)})
               | from_entries) as $peers
            | [.[] | select(.name == "holochain_dht_info")
                | {label: .labels.network_label,
                   peers: $peers[[.labels.conductor, .labels.app_id, .labels.role, .labels.dna] | tostring]}]
            | group_by(.label)
            | map({labels: "{network_label=\"\(.[0].label)\"}", value: (map(.peers) | min)})' > dht-expected.json
      echo "DHT peers expected:"
      jq -c '.[]' dht-expected.json
      test "$(jq length dht-expected.json)" = 13

      jq -n \
        --slurpfile down down.json --slurpfile dht dht.json --slurpfile expected dht-expected.json \
        --arg conductors "$(target 'Conductors up' A)" --arg status "$(target 'Fleet status' C)" \
        --arg peers "$(target 'DHT peers' A)" --arg gossip "$(target 'DHT seconds since last gossip' A)" \
        --arg held "$(target 'DHT ops held here vs best peer' A)" --arg best "$(target 'DHT ops held here vs best peer' B)" '
          {
            rule_files: [],
            evaluation_interval: "1m",
            tests: [
              # Workshop up, Moss stopped, one instance: the node reads down.
              {
                interval: "1m",
                input_series: $down[0],
                promql_expr_test: [
                  {expr: $conductors, eval_time: "5m", exp_samples: [{labels: "{instance=\"home\"}", value: 0}]},
                  {expr: $status, eval_time: "5m", exp_samples: [{labels: "{instance=\"home\"}", value: 0}]}
                ]
              },
              {
                interval: "1m",
                input_series: $dht[0],
                promql_expr_test: [
                  {expr: $peers, eval_time: "5m", exp_samples: $expected[0]},
                  {expr: "count(\($gossip))", eval_time: "5m", exp_samples: [{labels: "{}", value: ($expected[0] | length)}]},
                  {expr: "count(\($held))", eval_time: "5m", exp_samples: [{labels: "{}", value: ($expected[0] | length)}]},
                  {expr: "count(\($best))", eval_time: "5m", exp_samples: [{labels: "{}", value: ($expected[0] | length)}]}
                ]
              }
            ]
          }' > tests.json
      promtool test rules tests.json

      # Legends: never a machine key, and a conductor series that keeps its
      # conductor label says which conductor a line is.
      jq -r '
        [.panels[] | ., (.panels // [])[] | .title as $t | (.targets // [])[]
          | select(.legendFormat != null and (.expr | test("holochain_")))
          | {title: $t, expr, legend: .legendFormat}] as $targets
        | [$targets[] | select(.legend | test("\\{\\{ *(app_id|role|dna) *\\}\\}"))] as $keys
        | [$targets[] | select((.expr | test("holochain_conductor_")) and (.expr | test(" by \\(") | not)
                               and (.legend | test("\\{\\{ *conductor *\\}\\}") | not))] as $unnamed
        | if $keys != [] then error("legends that show a machine key: \($keys)")
          elif $unnamed != [] then error("conductor lines whose legend does not say which conductor: \($unnamed)")
          else "\($targets | length) holochain legends checked" end' $dashboard
      touch $out
    '';

  inherit runs;
}
