# The names file for the Moss node's exporter: the names given in Nix, plus
# what the exporter's previous file says about each app it listed.
#
# Run with -n. Inputs:
#   $static  (--slurpfile) the names file built from Nix: {apps, kinds, expected}
#   $seen    (--rawfile) the exporter's previous textfile, or empty
#   $group   what to call every Moss group app
#
# From the previous file's holochain_app_info lines it takes, for each app, its
# installed_app_id and its kind. Every group app gets $group as its name and is
# expected, so the group keeps its name and reads "Not running" if the
# conductor stops listing it. Every app keeps its kind, which the exporter
# reads only for an expected app the conductor does not list, whose bundle and
# so whose kind it cannot see (it would read "Tool").
#
# A name given in Nix always wins over $group. Label values in the textfile are
# escaped by the exporter; installed_app_ids and kinds hold no quote.

($static[0] // {}) as $s
| [ $seen | split("\n")[]
    | select(startswith("holochain_app_info{"))
    | capture("app_id=\"(?<id>[^\"]*)\".*,app_kind=\"(?<kind>[^\"]*)\"")
  ] as $apps
| [ $apps[] | select(.id | startswith("group#")) | .id ] as $groups
| $s
| .apps = (reduce $apps[] as $a ((.apps // {});
    .[$a.id] = ({kind: $a.kind}
      + (if ($a.id | startswith("group#")) and $group != "" then {name: $group} else {} end)
      + (.[$a.id] // {}))))
| .expected = (((.expected // []) + $groups) | unique)
