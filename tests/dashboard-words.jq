# What a person reads where a query answers with a stand-in rather than a
# figure: 1e9 for "no readings" or "never heard", and an empty cell for a part
# nobody else runs yet or with nobody to compare. The values mean nothing on
# their own, so a lost or recoloured mapping would put a bare 1000000000, or a
# red word on a lone node, on screen while every query still answers.
#
# Grafana resolves a value through a field's mappings in order and takes the
# first that matches: a value mapping by its text, a range with a missing end
# open on that side, a special "null" for an empty cell. mapped/1 does the
# same, so the check reads each stand-in the way the page does.
#
# Input: every dashboard file as a separate JSON document (jq -n with inputs).

def grey: "#8e8e8e";

def mapped($v):
  first(.[]? | . as $m
    | if $m.type == "value" then ($m.options[$v | tostring] // empty)
      elif $m.type == "range" then
        select($v != null
          and ($m.options.from == null or $v >= $m.options.from)
          and ($m.options.to == null or $v <= $m.options.to))
        | $m.options.result
      elif $m.type == "special" and $m.options.match == "null" then select($v == null) | $m.options.result
      else empty
      end)
  // null;

def panels: .panels[]? | ., (.panels // [])[];

# The mappings of one panel, or of one of its fields by the name the table
# shows it under, among all the dashboards.
def mappings($all; $uid; $title; $field):
  [$all[] | select(.uid == $uid) | panels | select(.title == $title and .type != "row")]
  | if length != 1 then error("\($uid): no single panel titled \($title | tojson)") else .[0] end
  | if $field == null then .fieldConfig.defaults.mappings
    else [.fieldConfig.overrides[] | select(.matcher == {id: "byName", options: $field})
          | .properties[] | select(.id == "mappings") | .value][0]
    end;

# Each stand-in, where it shows, and what a person must read for it.
def expected: [
  {uid: "holochain-now", title: "Are these readings current?", field: null, value: 1000000000, text: "No readings", color: "red"},
  {uid: "holochain-now", title: "Last heard from others, per app", field: null, value: 1000000000, text: "never", color: "red"},
  {uid: "holochain-network", title: "Last heard from others, per node", field: null, value: 1000000000, text: "never", color: "red"},
  {uid: "holochain-node", title: "Is each app part connected, complete and recent?", field: "Last heard", value: 1000000000, text: "never", color: "red"},
  {uid: "holochain-node", title: "Is each app part connected, complete and recent?", field: "Last heard", value: null, text: "nobody else yet", color: grey},
  {uid: "holochain-node", title: "Is each app part connected, complete and recent?", field: "Holds", value: null, text: "nobody to compare", color: grey},
  # A real figure must not be taken for a stand-in.
  {uid: "holochain-node", title: "Is each app part connected, complete and recent?", field: "Last heard", value: 42, text: null, color: null},
  {uid: "holochain-now", title: "Are these readings current?", field: null, value: 12, text: null, color: null}
];

[inputs] as $all
| [expected[] | . as $e
   | (mappings($all; $e.uid; $e.title; $e.field) | mapped($e.value)) as $r
   | select(($r.text // null) != $e.text or ($r.color // null) != $e.color)
   | "\($e.uid): \($e.title | tojson)\(if $e.field then " column " + ($e.field | tojson) else "" end) shows \($e.value | tojson) as \($r // "the bare value" | tojson), not \({text: $e.text, color: $e.color} | tojson)"] as $offences
| if $offences != [] then error("\n" + ($offences | join("\n")))
  else "\(expected | length) stand-ins read as words, and figures as figures"
  end
