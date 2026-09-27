# Checks on the provisioned dashboards (modules/dashboards) that need no VM.
#
# dashboardLabels reads the JSON: no machine key on a screen, every panel
# described, no uid twice. dashboardQueries runs the Holochain queries of every
# dashboard through promtool, on the rule file the grafana module renders and
# on what the exporter writes for two conductors on one instance plus a clone
# cell, the shapes a VM with one conductor does not have.
#
# Each check is also run on broken copies of its input, one fault at a time,
# and must fail on every one for the reason it names: a check that cannot fail
# proves nothing.
{
  pkgs,
  # The rendered rule file (holochain-grafana with its default states).
  rules,
  # The exporter's runs on the fixture conductors (tests/metrics.nix).
  runs,
  # The exporter's jq programs, for the clone cell's textfile.
  jqLib,
  dashboards ? ../modules/dashboards,
}: let
  labelsJq = ./dashboard-labels.jq;
in {
  dashboardLabels =
    pkgs.runCommand "dashboard-labels" {
      nativeBuildInputs = [pkgs.jq];
    } ''
      check() { jq -n -r -f ${labelsJq} "$@"; }
      check ${dashboards}/*.json

      # One fault per copy of the dashboards; the check must fail on each,
      # and name the fault.
      broken() {
        local reason=$1 file=$2 edit=$3
        rm -rf copy && cp -r --no-preserve=mode ${dashboards} copy
        jq "$edit" "copy/$file" > copy/edited && mv copy/edited "copy/$file"
        if check copy/*.json > broken.log 2>&1; then
          echo "still passes with $reason" >&2
          exit 1
        fi
        if ! grep -qF -- "$reason" broken.log; then
          echo "failed, but not for $reason:" >&2
          cat broken.log >&2
          exit 1
        fi
        echo "fails as it should: $reason"
      }
      first_target='([.. | objects | select(has("targets") and .type == "timeseries")] | first | .title) as $t
        | (.. | objects | select(.title? == $t) | .targets[0])'
      broken "shows the label app_id" holochain-now.json "$first_target.legendFormat = \"{{app_id}}\""
      broken "has no legend" holochain-network.json "$first_target |= del(.legendFormat)"
      broken "has no description" holochain-node.json '(.. | objects | select(.title? == "Conductors") | .description) = ""'
      broken "display name shows the label dna" holochain-node.json \
        '(.. | objects | select(.title? == "Conductors") | .fieldConfig.defaults.displayName) = "''${__field.labels.dna}"'
      broken "keeps every label" holochain-fleet.json \
        '(.. | objects | select(.title? == "Which node needs attention?") | .transformations) |= map(select(.id != "filterFieldsByName"))'
      broken "shows the column instance" holochain-fleet.json \
        '(.. | objects | select(.title? == "What needs a human?") | .transformations[] | select(.id == "filterFieldsByName") | .options.include.names) += ["instance"]'
      broken "shows the column dna" holochain-node.json \
        '(.. | objects | select(.title? == "Is each app part connected, complete and recent?") | .fieldConfig.overrides) |= map(select(.matcher.options != "dna"))'
      broken "is used by" holochain-network.json '.uid = "holochain-node"'
      touch $out
    '';

  # Every query of every dashboard that reads Holochain series, with its
  # variables filled as Grafana fills them, must answer on the homelab's shape
  # (Workshop and Moss on one instance, plus a conductor with a clone cell,
  # which shares conductor, app_id and role with the cell it came from, so a
  # join on fewer labels than the full key is many-to-many). The node's
  # status must be its worst conductor's, and the part table must have one row
  # per DHT, clone included.
  dashboardQueries =
    pkgs.runCommand "dashboard-queries" {
      nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli];
    } ''
      # A third conductor with one app in two DHTs of one role, the second a
      # clone, through the same jq the exporter runs.
      printf '%s\n%s\n%s\n' \
        '[{"installed_app_id":"notes","status":{"type":"enabled"},"manifest":{"name":"notes"},"cell_info":{"main":[
           {"type":"provisioned","value":{"cell_id":{"dna_hash":"dnaA","agent_pub_key":"k"}}},
           {"type":"cloned","value":{"clone_id":"main.0","cell_id":{"dna_hash":"dnaB","agent_pub_key":"k"}}}]}}]' \
        '{"dnaA":{},"dnaB":{}}' null \
        | jq -n -r -L ${jqLib} --arg conductor Clones --argjson now 1790484800 \
            -f ${jqLib}/dht-metrics.jq > clones.prom
      printf 'holochain_conductor_up{conductor="Clones"} 1\nholochain_conductor_metrics_scrape_timestamp_seconds{conductor="Clones"} 0\n' >> clones.prom

      # promtool input: every sample line of the files on one instance named
      # homelab, readings that keep pace with the test clock, the target's up
      # series, and one failed unit, so the problem tables have a row.
      series() {
        cat "$@" | grep -v '^#' \
          | sed -E 's/^([a-z_]+)\{/\1{instance="homelab:9100",job="holochain-nodes",node="homelab",/' \
          | jq -R 'capture("^(?<s>.*) (?<v>[^ ]+)$")
              | {series: .s,
                 values: (if (.s | startswith("holochain_conductor_metrics_scrape_timestamp_seconds{"))
                          then "0+60x60" else "\(.v)+0x60" end)}' \
          | jq -s '. + [{series: "up{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\"}", values: "1+0x60"},
                       {series: "node_systemd_unit_state{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\",name=\"x.service\",state=\"failed\"}", values: "1+0x60"}]'
      }
      series ${runs}/holochain-conductor.prom ${runs}/moss-node.prom clones.prom > up.json
      series ${runs}/holochain-conductor.prom ${runs}/moss-down.prom > down.json
      dhts=$(jq '[.[] | select(.series | startswith("holochain_dht_peers{"))] | length' up.json)
      echo "DHTs on the homelab shape: $dhts"
      test "$dhts" = 13

      # A DNA of the fixtures for the network page: the connected chat's.
      network=$(jq -r '[.[] | select(.series | startswith("holochain_dht_info{") and contains("network_label=\"General chat: Messages\""))]
        | first | .series | capture("dna=\"(?<d>[^\"]+)\"").d' up.json)
      echo "network page variable: $network"

      # Every target of every dashboard as {dashboard, title, ref, expr}, with
      # the variables Grafana would fill: All (.*) for the multi-value ones,
      # the node, the network and the room app the fixtures have.
      for f in ${dashboards}/*.json; do
        jq -c --arg network "$network" '
          . as $d | [.panels[] | ., (.panels // [])[]] | .[] | .title as $title
          | (.targets // [])[]
          | {dashboard: $d.uid, title: $title, ref: .refId,
             expr: (.expr
               | gsub("\\$\\{units:raw\\}"; "holochain-conductor.service")
               | gsub("\\$\\{room_app\\}"; "requests-and-offers")
               | gsub("\\$\\{room_part\\}"; "requests_and_offers")
               | gsub("\\$network"; $network)
               | gsub("\\$node"; "homelab")
               | gsub("\\$(site|conductor)"; ".*"))}' "$f"
      done | jq -s . > targets.json
      if jq -e 'any(.[]; .expr | contains("$"))' targets.json > /dev/null; then
        jq -c '.[] | select(.expr | contains("$"))' targets.json >&2
        echo "a variable is left unfilled" >&2
        exit 1
      fi

      # The Holochain queries: a query on node_exporter's own series (a
      # metric named node_*, not a rule such as holochain:node_state) has none
      # of them here, and vmTestGrafana runs those. "Same data everywhere"
      # needs two nodes on one DNA, which one instance cannot have.
      jq '[.[] | select(.expr | test("holochain")) | select(.expr | test("(^|[^a-z_:])node_[a-z]") | not)
           | select(.title != "Same data everywhere")]' targets.json > holochain.json
      echo "Holochain queries: $(jq length holochain.json) of $(jq length targets.json)"

      tests() {
        jq -n --slurpfile targets "$1" --slurpfile up up.json --slurpfile down down.json '
          {
            rule_files: ["${rules}"],
            evaluation_interval: "1m",
            tests: [
              {
                name: "every Holochain query answers",
                interval: "1m",
                input_series: $up[0],
                promql_expr_test: [$targets[0][]
                  | {expr: "count(\(.expr)) > bool 0", eval_time: "30m",
                     exp_samples: [{labels: "{}", value: 1}]}]
              },
              {
                name: "the node table and the part table",
                interval: "1m",
                input_series: $up[0],
                promql_expr_test: [
                  ($targets[0][] | select(.dashboard == "holochain-node" and .title == "Is each app part connected, complete and recent?")
                    # Holds exists only for the parts that have a peer: three
                    # of the Moss group and two of the connected chat.
                    | {expr: "count(\(.expr))", eval_time: "30m",
                       exp_samples: [{labels: "{}", value: (if .ref == "C" then 5 else 13 end)}]})
                ]
              },
              {
                name: "Moss stopped: the node reads Holochain not answering",
                interval: "1m",
                input_series: $down[0],
                promql_expr_test: [
                  ($targets[0][] | select(.dashboard == "holochain-fleet" and .title == "Which node needs attention?" and .ref == "A")
                    | {expr, eval_time: "30m", exp_samples: [{labels: "{node=\"homelab\"}", value: 1}]}),
                  ($targets[0][] | select(.dashboard == "holochain-now" and .title == "Which machines are on?")
                    | {expr, eval_time: "30m",
                       exp_samples: [{labels: "holochain:node_state{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\"}", value: 1}]})
                ]
              }
            ]
          }'
      }
      tests holochain.json > tests.json
      echo "expressions under test: $(jq '[.tests[].promql_expr_test[]] | length' tests.json)"
      test "$(jq '.tests[1].promql_expr_test | length' tests.json)" = 6
      test "$(jq '.tests[2].promql_expr_test | length' tests.json)" = 2
      promtool test rules tests.json

      # Broken on purpose: a rule name misspelt in one query, and a part
      # table joined on fewer labels than the full key of a DHT. Each must
      # fail its test.
      broken() {
        local reason=$1 edit=$2 says=$3
        jq "$edit" holochain.json > broken-targets.json
        if cmp -s holochain.json broken-targets.json; then
          echo "the edit for $reason changed nothing" >&2
          exit 1
        fi
        tests broken-targets.json > broken.json
        if promtool test rules broken.json > broken.log 2>&1; then
          echo "still passes with $reason" >&2
          exit 1
        fi
        if ! grep -qF -- "$says" broken.log; then
          echo "failed, but without saying $says:" >&2
          cat broken.log >&2
          exit 1
        fi
        echo "fails as it should: $reason ($says)"
      }
      broken "a misspelt rule" \
        'map(if .title == "Is each app working on each node?" then .expr |= sub("holochain:app_state:named"; "holochain:app_state:nammed") else . end)' \
        "got: nil"
      broken "a join on part of the key" \
        'map(if .title == "Is each app part connected, complete and recent?" then .expr |= gsub("instance, conductor, app_id, role, dna"; "instance, conductor, app_id, role") else . end)' \
        "many-to-many"
      touch $out
    '';
}
