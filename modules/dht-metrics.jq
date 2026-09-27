# Turns the conductor's `list-apps` and `dump-network-metrics --include-dht-summary`
# replies into node_exporter textfile series, one set per DHT the conductor is in,
# plus two info families that carry the names a dashboard shows.
#
# Run with -n and `-L` pointing at the directory holding families.jq. Three
# documents arrive on stdin: list-apps, then dump-network-metrics, each one either
# the reply or null when that call did not answer, then the names file (optional;
# anything but an object reads as {}). They come through stdin rather than
# --argjson because a list-apps reply carries every DNA's properties and grows past
# the 128 KiB a single command-line argument may hold (Linux MAX_ARG_STRLEN); a
# Moss node with three apps already answers 110 KB.
#
# list-apps: [{installed_app_id, status: {type}, manifest: {name}, cell_info:
#   {<role>: [{type, value: {cell_id: {dna_hash, agent_pub_key}}}]}}]. Provisioned
#   and cloned cells carry a cell_id; stem cells do not and are skipped.
# dump-network-metrics: {<dna_hash>: {fetch_state_summary: {pending_requests:
#   {<op id>: [peer url]}}, gossip_state_summary: {peer_meta: {<peer url>:
#   {last_gossip_timestamp (microseconds), completed_rounds, dht_op_count,
#   peer_timeouts, ...}}, local_op_count, ...}, local_agents}}. Kitsune2's
#   GossipStateSummary, PeerMeta and FetchStateSummary are declared identically in
#   kitsune2_api 0.4.1 (the 0.6 line) and 0.5.0 (the 0.7 line); the shape above was
#   read from a Holochain 0.6.1 conductor on 2026-09-27.
# names: {apps: {<installed_app_id>: {name, roles: {<role>: part name}}},
#   kinds: {<app kind>: {<role>: part name}}, expected: [<installed_app_id>]}.
#   Everything that knows a name puts it here (the edgenode module from its happs
#   options, a Moss wrapper from its own), so this is the only writer of the two
#   info families and a dashboard join never meets two rows for one key.
#
# $conductor names the conductor; $now is the scrape time in seconds since the epoch.
#
# Data series carry machine keys only: conductor, app_id (the installed_app_id),
# role and dna. Names go on holochain_app_info and holochain_dht_info, joined at
# query time, so renaming an app never splits a data series.
#
# A cell whose DNA the reply does not mention is in no network the conductor
# reports right now, and gets no series rather than zeros that would read as a
# DHT with no peers and no data. When either call did not answer, no DHT gets
# any series, for the same reason. holochain_app_info needs list-apps only, and
# an app the names file expects but list-apps does not list (or list-apps did
# not answer) is still written, with status "expected", so it reads as not
# running instead of vanishing.
#
# Every sample line must end in a number and every label value must be quoted and
# escaped: node_exporter drops the whole textfile on one bad line, and with it
# every holochain_conductor_* series.

include "families";

def num: if type == "number" then . else 0 end;

def str: if type == "string" then . else "" end;

# "requests_and_offers" reads "Requests and offers", "kando" reads "Kando".
def pretty:
  gsub("[_-]+"; " ") | gsub("^ +| +$"; "")
  | if . == "" then . else (.[0:1] | ascii_upcase) + .[1:] end;

# Role ids often carry a one-letter prefix before a capital: "rFiles" is Files.
def part_pretty: sub("^[a-z](?=[A-Z])"; "") | pretty;

# Moss installs every tool as `applet#<hash>` and the group itself as
# `group#<hash>`; its bundles are named with an "h" before a capital (hVines).
def is_moss: startswith("applet#") or startswith("group#");

def labels($o):
  "{" + ([$o | to_entries[] | "\(.key)=\"\(.value | escape)\""] | join(",")) + "}";

input as $apps
| input as $metrics
| ((try input catch null) | if type == "object" then . else {} end) as $names
| (($names.apps // {}) | if type == "object" then . else {} end) as $named
| (($names.kinds // {}) | if type == "object" then . else {} end) as $kinds
| ([($names.expected // []) | if type == "array" then .[] else empty end | strings] | unique) as $expected
# What the names file says about one app, and the non-empty string it gives,
# if any, for a name.
| def entry($id): $named[$id] | if type == "object" then . else {} end;
  def given: if type == "string" and . != "" then . else null end;
  (if ($apps | type) == "array" then [$apps[] | objects] else null end) as $listed

# One entry per installed app: its fallback name comes from the bundle, and two
# apps that would share one (two chats of the same Moss tool) are numbered in
# the order of their installed_app_id, so no two apps read alike and no hash is
# ever the way to tell them apart.
| [ ($listed // [])[]
    | (.installed_app_id | str) as $id
    | select($id != "")
    | ($id | is_moss) as $moss
    | ((.manifest.name // "") | str) as $bundle
    | (if $moss then
         (if ($id | startswith("group#")) then "Group"
          else ($bundle | sub("^h(?=[A-Z])"; "") | pretty | if . == "" then "Tool" else . end) end)
       else
         (if $bundle == "" then $id else $bundle end | pretty)
       end) as $fallback
    | {
        id: $id, moss: $moss, fallback: $fallback,
        status: (.status.type // "unknown" | tostring | ascii_downcase | gsub("[^a-z_]"; "_")),
        roles: ((.cell_info // {}) | if type == "object" then keys | length else 0 end)
      }
  ]
| (group_by(.fallback)
    | map(if length == 1 then [.[0] + {auto: .[0].fallback}]
          else sort_by(.id) | to_entries | map(.value + {auto: "\(.value.fallback) \(.key + 1)"}) end)
    | add // []
    | map(. + {name: ((entry(.id).name | given) // .auto)}
          | . + {kind: (if .moss then .fallback else .name end)}
          | {key: .id, value: .})
    | from_entries) as $info

# Apps Nix manages that the conductor did not list, or all of them when
# list-apps did not answer.
| [ $expected[]
    | . as $id
    | select($info | has($id) | not)
    | ((entry($id).name | given) // ($id | pretty)) as $name
    | {id: $id, name: $name, kind: $name, status: "expected"}
  ] as $missing

| (if $listed == null or ($metrics | type) != "object" then []
   else
    [ $listed[]
      | (.installed_app_id | str) as $app
      | select($app != "")
      | $info[$app] as $a
      | (.cell_info // {}) | to_entries[]
      | .key as $role
      | .value[]?
      | (.value.cell_id.dna_hash? // empty) as $dna
      | select($dna | type == "string")
      | select($metrics | has($dna))
      | ($metrics[$dna] // {}) as $m
      | ($m.gossip_state_summary // {}) as $g
      | [($g.peer_meta // {}) | .[]? | objects] as $peers
      | ([$peers[].last_gossip_timestamp | num] | max // 0) as $last
      | ((entry($app).roles | objects | .[$role] | strings)
         // ($kinds[$a.kind] | objects | .[$role] | strings)
         // null) as $given
      | ($given // (if $a.roles == 1 then "" else ($role | part_pretty) end)) as $part
      | {
          key: {conductor: $conductor, app_id: $app, role: $role, dna: $dna},
          names: {
            app_name: $a.name, app_kind: $a.kind, part_name: $part,
            network_label: (if $part == "" then $a.name else "\($a.name): \($part)" end)
          },
          peers: ($peers | length),
          local_ops: ($g.local_op_count | num),
          peer_ops: ([$peers[].dht_op_count | num] | max // 0),
          pending: (($m.fetch_state_summary.pending_requests // {}) | if type == "object" then length else 0 end),
          since: (if $last > 0 then ([($now - ($last / 1000000)) | floor, 0] | max) else -1 end),
          rounds: ([$peers[].completed_rounds | num] | add // 0),
          timeouts: ([$peers[].peer_timeouts | num] | add // 0)
        }
    ]
   end) as $rows

| ([$info[]] + $missing) as $apps_named
| (if $apps_named == [] then empty
   else
     family("holochain_app_info"),
     ($apps_named | sort_by(.id)[]
       | "holochain_app_info\(labels({conductor: $conductor, app_id: .id, app_name: .name, app_kind: .kind, status: .status})) 1")
   end),
  (if $rows == [] then empty
   else
     def series($name; $field):
       family($name), ($rows[] | "\($name)\(labels(.key)) \(.[$field])");
     family("holochain_dht_info"),
     ($rows[] | "holochain_dht_info\(labels(.key + .names)) 1"),
     series("holochain_dht_peers"; "peers"),
     series("holochain_dht_local_ops"; "local_ops"),
     series("holochain_dht_peer_ops"; "peer_ops"),
     series("holochain_dht_pending_fetches"; "pending"),
     series("holochain_dht_seconds_since_gossip"; "since"),
     series("holochain_dht_completed_rounds_total"; "rounds"),
     series("holochain_dht_peer_timeouts_total"; "timeouts")
   end)
