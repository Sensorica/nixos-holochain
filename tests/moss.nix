# Checks on the Moss node's metrics that need no VM.
#
# mossDashboard runs nixos-holochain's own label check on the Sensorica page
# together with the dashboards it ships: no machine key on a screen, every
# panel described, and no uid that one of them already uses. It also asks the
# tool table and the group's share to say in words why they are empty.
#
# mossNames runs moss-node-names.jq on a previous exporter file, then feeds the
# names file it writes to nixos-holochain's dht-metrics.jq with the Moss
# conductor not answering, and reads what the dashboards would show: the group
# by its name, each tool by its Nix name and kind, both as expected apps.
#
# Each check is also run on broken copies of its input, one fault at a time,
# and must fail on every one for the reason it names: a check that cannot fail
# proves nothing.
{
  pkgs,
  nixos-holochain,
  # The exporter, for its jq programs (dht-metrics.jq and families.jq).
  exporter,
  dashboard ? ../modules/dashboards-moss/sensorica-moss-node.json,
  namesJq ? ../modules/moss-node-names.jq,
}: {
  mossDashboard =
    pkgs.runCommand "moss-dashboard" {
      nativeBuildInputs = [pkgs.jq];
    } ''
      check() {
        jq -n -r -f ${nixos-holochain}/tests/dashboard-labels.jq ${nixos-holochain}/modules/dashboards/*.json "$1" || return 1
        # The tool table and the group's share are empty exactly when the
        # Moss node reports nothing; each must say so in words, not with
        # Grafana's bare "No data" or a neutral "nobody to compare".
        jq -e '[.. | objects | select(.title? == "Is each tool connected and complete?" or .title? == "Group data held")
                | (.fieldConfig.defaults.noValue // "") | length > 0] | length == 2 and all' "$1" > /dev/null \
          || { echo "a panel says nothing when empty" >&2; return 1; }
      }
      check ${dashboard}

      broken() {
        local reason=$1 edit=$2
        jq "$edit" ${dashboard} > copy.json
        if cmp -s ${dashboard} copy.json; then
          echo "the edit for $reason changed nothing" >&2
          exit 1
        fi
        if check copy.json > broken.log 2>&1; then
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
      broken "shows the label app_id" \
        '(.. | objects | select(.title? == "Items still on their way") | .targets[0].legendFormat) = "{{app_id}}"'
      broken "shows the column dna" \
        '(.. | objects | select(.title? == "Is each tool connected and complete?") | .transformations[] | select(.id == "filterFieldsByName") | .options.include.names) += ["dna"]'
      broken "has no description" \
        '(.. | objects | select(.title? == "Tools hosted") | .description) = ""'
      broken "is used by" '.uid = "holochain-node"'
      broken "a panel says nothing when empty" \
        'del(.. | objects | select(.title? == "Is each tool connected and complete?") | .fieldConfig.defaults.noValue)'
      touch $out
    '';

  mossNames =
    pkgs.runCommand "moss-names" {
      nativeBuildInputs = [pkgs.jq];
    } ''
      # The names Nix gives: one tool named, the part table of each kind.
      cat > static.json <<'EOF'
      {"apps": {"applet#uhc$e$kaaa": {"name": "General chat"}},
       "kinds": {"Vines": {"rVines": "Messages", "rFiles": "Files"}, "Group": {"group": "Members and tools"}},
       "expected": ["applet#uhc$e$kaaa"]}
      EOF
      # The exporter's previous file: the named tool, a tool Nix does not name,
      # and the group, as it writes them.
      cat > seen.prom <<'EOF'
      # HELP holochain_app_info An installed app.
      # TYPE holochain_app_info gauge
      holochain_app_info{conductor="Moss",app_id="applet#uhc$e$kaaa",app_name="General chat",app_kind="Vines",status="enabled"} 1
      holochain_app_info{conductor="Moss",app_id="applet#uhc$e$kbbb",app_name="Vines",app_kind="Vines",status="enabled"} 1
      holochain_app_info{conductor="Moss",app_id="group#4zHN/lmO=#null",app_name="Group",app_kind="Group",status="enabled"} 1
      holochain_dht_peers{conductor="Moss",app_id="group#4zHN/lmO=#null",role="group",dna="uhC0kx"} 0
      EOF

      check() {
        local program=$1
        jq -n --slurpfile static static.json --rawfile seen seen.prom --arg group Sensorica \
          -f "$program" > names.json || { echo "the names program failed" >&2; return 1; }
        # A first run, with no previous file, keeps the Nix names as they are.
        jq -n --slurpfile static static.json --rawfile seen /dev/null --arg group Sensorica \
          -f "$program" > first.json || { echo "the names program failed with no previous file" >&2; return 1; }
        jq -e --slurpfile s static.json '.apps == $s[0].apps and .expected == $s[0].expected' first.json > /dev/null \
          || { echo "a first run changes the Nix names" >&2; return 1; }

        # The Moss conductor does not answer: list-apps and the DHT reply are
        # null, so every app on the page comes from the names file.
        printf 'null\nnull\n%s\n' "$(cat names.json)" \
          | jq -n -r -L ${exporter.jqLib} --arg conductor Moss --argjson now 0 -f ${exporter.jqLib}/dht-metrics.jq > out.prom \
          || { echo "dht-metrics.jq failed on the names file" >&2; return 1; }
        want() {
          grep -qxF -- "$1" out.prom || { echo "$2: no line $1 in:" >&2; cat out.prom >&2; return 1; }
        }
        # check runs inside `if`, where a failing command does not stop it, so
        # every step returns its own failure.
        want 'holochain_app_info{conductor="Moss",app_id="group#4zHN/lmO=#null",app_name="Sensorica",app_kind="Group",status="expected"} 1' \
          "the group lost its name or its place among the expected apps" || return 1
        want 'holochain_app_info{conductor="Moss",app_id="applet#uhc$e$kaaa",app_name="General chat",app_kind="Vines",status="expected"} 1' \
          "the named tool lost its name or its kind" || return 1
        if grep -qF 'app_id="applet#uhc$e$kbbb"' out.prom; then
          echo "a tool Nix does not name became expected" >&2
          return 1
        fi
      }
      check ${namesJq}
      echo "the group, the named tool and their kinds reach the dashboards"

      broken() {
        local reason=$1 edit=$2
        sed -E "$edit" ${namesJq} > copy.jq
        if cmp -s ${namesJq} copy.jq; then
          echo "the edit for $reason changed nothing" >&2
          exit 1
        fi
        if check copy.jq > broken.log 2>&1; then
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
      broken "the group lost its name or its place among the expected apps" 's/ \+ \$groups\)/)/'
      broken "the named tool lost its name or its kind" 's/^( *)\+ \(\.\[\$a\.id\] \/\/ \{\}\)\)\)\)/\1)))/'
      broken "a tool Nix does not name became expected" \
        's/select\(\.id \| startswith\("group#"\)\) \| \.id/.id/'
      touch $out
    '';
}
