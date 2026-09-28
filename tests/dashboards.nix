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
      broken "display name shows the label every label" holochain-now.json \
        '(.. | objects | select(.title? == "Which machines are on?") | .fieldConfig.defaults.displayName) = "''${__field.labels}"'
      broken "shows the variable network, whose value is not a name" holochain-network.json \
        '(.. | objects | select(.title? == "Did it reach everyone? Data held on each node") | .title) = "Did ''${network} reach everyone?"'
      broken "shows the field instance" holochain-now.json \
        '(.. | objects | select(.title? == "Which machines are on?") | .options.reduceOptions) |= (.fields = "/^instance$/" | .values = true)'
      broken "keeps every label" holochain-fleet.json \
        '(.. | objects | select(.title? == "Which node needs attention?") | .transformations) |= map(select(.id != "filterFieldsByName"))'
      broken "shows the column instance" holochain-fleet.json \
        '(.. | objects | select(.title? == "What needs a human?") | .transformations[] | select(.id == "filterFieldsByName") | .options.include.names) += ["instance"]'
      broken "shows the column dna" holochain-node.json \
        '(.. | objects | select(.title? == "Is each app part connected, complete and recent?") | .fieldConfig.overrides) |= map(select(.matcher.options != "dna"))'
      broken "panel \"Is each service on this machine running?\" shows the column instance" holochain-node.json \
        '(.. | objects | select(.title? == "Is each service on this machine running?") | .transformations[] | select(.id == "filterFieldsByName") | .options.include.names) += ["instance"]'
      broken "is used by" holochain-network.json '.uid = "holochain-node"'
      touch $out
    '';

  # The words a person reads where a query answers with a stand-in (1e9 for
  # no readings or never heard, an empty cell for nobody else yet or nobody
  # to compare), resolved through each field's mappings as Grafana resolves
  # them (tests/dashboard-words.jq).
  dashboardWords =
    pkgs.runCommand "dashboard-words" {
      nativeBuildInputs = [pkgs.jq];
    } ''
      check() { jq -n -r -f ${./dashboard-words.jq} "$@"; }
      check ${dashboards}/*.json

      broken() {
        local reason=$1 file=$2 edit=$3 says=$4
        rm -rf copy && cp -r --no-preserve=mode ${dashboards} copy
        jq "$edit" "copy/$file" > copy/edited && mv copy/edited "copy/$file"
        if cmp -s "${dashboards}/$file" "copy/$file"; then
          echo "the edit for $reason changed nothing" >&2
          exit 1
        fi
        if check copy/*.json > broken.log 2>&1; then
          echo "still passes with $reason" >&2
          exit 1
        fi
        if ! grep -qF -- "$says" broken.log; then
          echo "failed, but without saying $says:" >&2
          cat broken.log >&2
          exit 1
        fi
        echo "fails as it should: $reason"
      }
      broken "the readings tile without its No readings range" holochain-now.json \
        '(.. | objects | select(.title? == "Are these readings current?") | .fieldConfig.defaults.mappings) = []' \
        '"Are these readings current?" shows 1000000000 as "the bare value"'
      broken "never recoloured green" holochain-network.json \
        '(.. | objects | select(.title? == "Last heard from others, per node") | .fieldConfig.defaults.mappings[0].options.result.color) = "green"' \
        'shows 1000000000 as {"text":"never","color":"green"'
      broken "an empty Last heard cell with no word" holochain-node.json \
        '(.. | objects | select(.title? == "Is each app part connected, complete and recent?") | .fieldConfig.overrides[]
          | select(.matcher.options == "Last heard") | .properties[] | select(.id == "mappings") | .value) |= map(select(.type != "special"))' \
        'column "Last heard" shows null as "the bare value"'
      broken "a never range that swallows real figures" holochain-node.json \
        '(.. | objects | select(.title? == "Is each app part connected, complete and recent?") | .fieldConfig.overrides[]
          | select(.matcher.options == "Last heard") | .properties[] | select(.id == "mappings") | .value[0].options.from) = 0' \
        'column "Last heard" shows 42 as {"text":"never"'
      touch $out
    '';

  # Every query of every dashboard that reads Holochain series, with its
  # variables filled as Grafana fills them, must answer on the homelab's shape
  # (Workshop and Moss on one instance, plus a conductor with a clone cell,
  # which shares conductor, app_id and role with the cell it came from, so a
  # join on fewer labels than the full key is many-to-many). The node's
  # status must be its worst conductor's, and the part table must have one row
  # per DHT, clone included.
  #
  # Answering is not enough for a query with a fallback, such as
  # `count(x == 1) or vector(0)`, which answers 0 whatever x is. So every
  # series selector a query reads (tests/query-selectors.jq) must also select
  # something here, and every rule it names must be recorded by the rule file.
  dashboardQueries =
    pkgs.runCommand "dashboard-queries" {
      nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli pkgs.yq-go];
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
      # series, one failed unit, so the problem tables have a row, and the
      # services the node lists: the conductor that runs Workshop, a gateway
      # that is stopped, so the fleet's list of services down has a row, and a
      # bootstrap server whose health reading keeps pace with the clock. The
      # Moss and Clones conductors are claimed by no unit.
      unit() {
        for state in active activating deactivating failed inactive; do
          jq -n -c --arg unit "$1" --arg state "$state" --arg v "$([ "$state" = "$2" ] && echo 1 || echo 0)" \
            '{series: "node_systemd_unit_state{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\",name=\"\($unit)\",state=\"\($state)\"}", values: "\($v)+0x60"}'
        done
      }
      {
        unit holochain-conductor.service active
        unit holochain-http-gateway.service inactive
        unit holochain-bootstrap.service active
      } | jq -s '. + [
        {series: "holochain_service_info{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\",conductor=\"Workshop\",name=\"holochain-conductor.service\",service=\"Holochain conductor (Workshop)\"}", values: "1+0x60"},
        {series: "holochain_service_info{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\",name=\"holochain-http-gateway.service\",service=\"HTTP gateway\"}", values: "1+0x60"},
        {series: "holochain_service_info{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\",name=\"holochain-bootstrap.service\",service=\"Local bootstrap and relay\"}", values: "1+0x60"},
        {series: "holochain_service_healthy{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\",name=\"holochain-bootstrap.service\"}", values: "1+0x60"},
        {series: "holochain_service_health_timestamp_seconds{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\",name=\"holochain-bootstrap.service\"}", values: "0+60x60"}]' > services.json
      series() {
        cat "$@" | grep -v '^#' \
          | sed -E 's/^([a-z_]+)\{/\1{instance="homelab:9100",job="holochain-nodes",node="homelab",/' \
          | jq -R 'capture("^(?<s>.*) (?<v>[^ ]+)$")
              | {series: .s,
                 values: (if (.s | startswith("holochain_conductor_metrics_scrape_timestamp_seconds{"))
                          then "0+60x60" else "\(.v)+0x60" end)}' \
          | jq -s '. + [{series: "up{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\"}", values: "1+0x60"},
                       {series: "node_systemd_unit_state{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\",name=\"x.service\",state=\"failed\"}", values: "1+0x60"}]
              + $services[0]' --slurpfile services services.json
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
      # of them here, and vmTestGrafana runs those.
      jq '[.[] | select(.expr | test("holochain")) | select(.expr | test("(^|[^a-z_:])node_[a-z]") | not)]' \
        targets.json > holochain.json
      echo "Holochain queries: $(jq length holochain.json) of $(jq length targets.json)"

      # The rules the rule file records.
      yq -o json '[.groups[].rules[] | select(has("record")) | .record]' ${rules} > records.json
      echo "recorded rules: $(jq length records.json)"

      # The promtool tests for a list of targets, after the rule names its
      # queries read are checked against the rule file. "Same data
      # everywhere" needs two nodes on one DNA, which one instance cannot
      # have: its query is left out of the answering test and its rule may
      # select nothing here, but the rule it names must still be recorded.
      tests() {
        jq -f ${./query-selectors.jq} "$1" > selectors.json
        jq -r --slurpfile records records.json \
          '.[] | capture("^(?<name>[A-Za-z_:][A-Za-z0-9_:]*)").name | select(contains(":"))
           | select(IN($records[0][]) | not) | "\(.) is not a recorded rule"' selectors.json > unrecorded.txt
        if [ -s unrecorded.txt ]; then
          cat unrecorded.txt >&2
          return 1
        fi
        jq -n --slurpfile targets "$1" --slurpfile selectors selectors.json --slurpfile up up.json --slurpfile down down.json '
          {
            rule_files: ["${rules}"],
            evaluation_interval: "1m",
            tests: [
              {
                name: "every Holochain query answers",
                interval: "1m",
                input_series: $up[0],
                promql_expr_test: [$targets[0][] | select(.title != "Same data everywhere")
                  | {expr: "count(\(.expr)) > bool 0", eval_time: "30m",
                     exp_samples: [{labels: "{}", value: 1}]}]
              },
              {
                name: "every series a query reads is there",
                interval: "1m",
                input_series: $up[0],
                promql_expr_test: [$selectors[0][] | select(startswith("holochain:dna_same_data") | not)
                  | {expr: "count(\(.)) > bool 0", eval_time: "30m",
                     exp_samples: [{labels: "{}", value: 1}]}]
              },
              {
                name: "the node table and the part table",
                interval: "1m",
                input_series: $up[0],
                promql_expr_test: [
                  ($targets[0][] | select(.dashboard == "holochain-node" and .title == "Is each app part connected, complete and recent?")
                    # Holds exists only for the parts that have a peer: three
                    # of the Moss group and two of the connected chat. Last
                    # heard leaves out the parts nobody else runs yet, which
                    # read grey rather than a red "never".
                    # Counted by __name__: a query that keeps its metric
                    # name splits the Grafana merge into a row per query.
                    | {expr: "count by (__name__) (\(.expr))", eval_time: "30m",
                       exp_samples: [{labels: "{}", value: ({C: 5, D: 5}[.ref] // 13)}]})
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
                       exp_samples: [{labels: "holochain:node_state{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\"}", value: 1}]}),
                  # The Moss node is a service of its own, and does not answer.
                  ($targets[0][] | select(.dashboard == "holochain-node" and .title == "Is each service on this machine running?")
                    | {expr: "max by (service) (\(.expr))", eval_time: "30m",
                       exp_samples: [
                         {labels: "{service=\"Holochain conductor (Workshop)\"}", value: 6},
                         {labels: "{service=\"HTTP gateway\"}", value: 1},
                         {labels: "{service=\"Local bootstrap and relay\"}", value: 6},
                         {labels: "{service=\"Holochain conductor (Moss)\"}", value: 2}]})
                ]
              },
              {
                name: "the services each node lists, by name, and the one that is down",
                interval: "1m",
                input_series: $up[0],
                promql_expr_test: [
                  # One row per service: the three the node lists, and a row
                  # for each conductor no unit claims, Moss as "Holochain conductor (Moss)".
                  ($targets[0][] | select(.dashboard == "holochain-node" and .title == "Is each service on this machine running?")
                    | {expr: "max by (service) (\(.expr))", eval_time: "30m",
                       exp_samples: [
                         {labels: "{service=\"Holochain conductor (Workshop)\"}", value: 6},
                         {labels: "{service=\"HTTP gateway\"}", value: 1},
                         {labels: "{service=\"Local bootstrap and relay\"}", value: 6},
                         {labels: "{service=\"Holochain conductor (Moss)\"}", value: 6},
                         {labels: "{service=\"Holochain conductor (Clones)\"}", value: 6}]}),
                  ($targets[0][] | select(.dashboard == "holochain-fleet" and .title == "Which services are not running?")
                    | {expr: "max by (node, service) (\(.expr))", eval_time: "30m",
                       exp_samples: [{labels: "{node=\"homelab\", service=\"HTTP gateway\"}", value: 1}]}),
                  # A stopped gateway turns the tile of the machine to A service is down.
                  ($targets[0][] | select(.dashboard == "holochain-now" and .title == "Which machines are on?")
                    | {expr, eval_time: "30m",
                       exp_samples: [{labels: "holochain:node_state{instance=\"homelab:9100\",job=\"holochain-nodes\",node=\"homelab\"}", value: 2}]})
                ]
              }
            ]
          }'
      }
      tests holochain.json > tests.json
      echo "expressions under test: $(jq '[.tests[].promql_expr_test[]] | length' tests.json)"
      echo "series selectors read: $(jq length selectors.json)"
      test "$(jq '.tests[2].promql_expr_test | length' tests.json)" = 6
      test "$(jq '.tests[3].promql_expr_test | length' tests.json)" = 3
      test "$(jq '.tests[4].promql_expr_test | length' tests.json)" = 3
      promtool test rules tests.json

      # Broken on purpose: a rule name misspelt in one query, in queries
      # whose vector fallback answers anyway, a metric and a label filter
      # behind such a fallback that select nothing, and a part table joined
      # on fewer labels than the full key of a DHT. Each must fail.
      broken() {
        local reason=$1 edit=$2 says=$3
        jq "$edit" holochain.json > broken-targets.json
        if cmp -s holochain.json broken-targets.json; then
          echo "the edit for $reason changed nothing" >&2
          exit 1
        fi
        if tests broken-targets.json > broken.json 2> broken.log \
          && promtool test rules broken.json >> broken.log 2>&1; then
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
        "holochain:app_state:nammed is not a recorded rule"
      broken "a misspelt rule behind a vector fallback" \
        'map(if .title == "Holochain silent" then .expr |= sub("holochain:conductor_state"; "holochain:conductor_stat") else . end)' \
        "holochain:conductor_stat is not a recorded rule"
      broken "a misspelt rule in the query the answering test leaves out" \
        'map(if .title == "Same data everywhere" then .expr |= sub("holochain:dna_same_data"; "holochain:dna_same_dat") else . end)' \
        "holochain:dna_same_dat is not a recorded rule"
      broken "a misspelt metric behind a vector fallback" \
        'map(if .title == "Apps" and .ref == "A" then .expr |= sub("holochain_app_info"; "holochain_app_infos") else . end)' \
        'count(holochain_app_infos{'
      broken "a label filter that selects nothing behind a vector fallback" \
        'map(if .dashboard == "holochain-network" and .title == "Lost contact" then .expr |= sub("dna=\""; "dna=\"no-such-") else . end)' \
        'count(holochain:dht_state{dna=\"no-such-'
      broken "a services table that reads the watched list, not the states" \
        'map(if .title == "Is each service on this machine running?" then .expr |= sub("holochain:service_state"; "holochain:service_watched") else . end)' \
        'got:'
      broken "a join on part of the key" \
        'map(if .title == "Is each app part connected, complete and recent?" then .expr |= gsub("instance, conductor, app_id, role, dna"; "instance, conductor, app_id, role") else . end)' \
        "many-to-many"
      broken "a part table query that keeps its metric name" \
        'map(if .title == "Is each app part connected, complete and recent?" and .ref == "B" then .expr |= sub(" [+] 0$"; "") else . end)' \
        "holochain:dht_peers:named"
      touch $out
    '';
}
