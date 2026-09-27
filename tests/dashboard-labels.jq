# What a person can read on the provisioned dashboards, checked from their
# JSON: no label outside the human ones reaches a legend, a display name, a
# table column or a stat's picked field, no text shows a variable whose value
# is a machine key, every panel says what it answers, and no two dashboards
# share a uid. Prints one line per dashboard and fails, listing every offence, when
# anything is off.
#
# Input: every dashboard file as a separate JSON document (jq -n with inputs),
# so input_filename can name the file.
#
# The one exception is the panel titled "Identity, for bug reports", whose
# job is to show the machine keys of one network for an issue report.

# The labels whose values are names a person reads: the node, its site and
# conductor, the app and its parts, a problem sentence, a watched unit and its
# state (both mapped to words by the dashboards), and the parts of a machine
# (a disk's mount point, a sensor).
def human: ["node", "site", "conductor", "app_name", "app_kind", "part_name", "network_label",
            "problem", "name", "state", "mountpoint", "chip", "sensor"];
# The value columns of a table query, which hold numbers, not labels.
def value_field: test("^Value( #[A-Z]+)?$");
def exempt: "Identity, for bug reports";

# Labels that are machine keys, which a stat must not pick as its shown field.
def machine_keys: ["__name__", "instance", "job", "app_id", "role", "dna"];
# Variables whose raw value is a name a person reads. Any other variable
# (network holds a DNA hash, room_app an installed app id) may be shown only
# through its text, and only when it is a query variable, whose text can
# differ from its value.
def named_variables: ["node", "site", "conductor", "room_label"];

def panels: .panels[]? | ., (.panels // [])[];
# Every {{label}} in a legend and every ${__field.labels.label} or {{label}} in
# a display name. A bare ${__field.labels} prints every label at once, and
# counts as the label "every label".
def legend_labels: [scan("\\{\\{ *([A-Za-z_][A-Za-z0-9_]*) *\\}\\}") | .[0]];
def display_labels: legend_labels + [scan("__field\\.labels\\.([A-Za-z_][A-Za-z0-9_]*)") | .[0]]
  + [scan("__field\\.labels\\[\"([^\"]+)\"\\]") | .[0]]
  + [scan("__field\\.labels(?![.\\[A-Za-z0-9_])") | "every label"];
# Every dashboard variable a string shows, as {name, format}: $name,
# ${name}, ${name:format} and [[name]]. Grafana's own (__all, __field...)
# are left to the rules above.
def variables_shown:
  [(scan("\\$\\{([A-Za-z_][A-Za-z0-9_]*)(?::([A-Za-z]+))?\\}"),
    scan("\\[\\[([A-Za-z_][A-Za-z0-9_]*)(?::([A-Za-z]+))?\\]\\]"),
    (scan("\\$([A-Za-z_][A-Za-z0-9_]*)") | . + [null]))
   | {name: .[0], format: .[1]} | select(.name | startswith("__") | not)];
# What a stat, gauge or bar gauge shows when it picks fields itself: the
# machine keys its reduceOptions.fields (a name, or a /regex/) would pick.
def picked_keys:
  (.options.reduceOptions.fields // "") as $fields
  | if $fields == "" then empty
    elif ($fields | test("^/.*/$")) then ($fields[1:-1]) as $re | machine_keys[] | select(test($re))
    else machine_keys[] | select(. == $fields)
    end;

# The columns a table shows: the row and column of a matrix, or the fields a
# filterFieldsByName transform keeps, less those an override hides. A table
# with neither shows every label of its series.
def shown_fields:
  ([.transformations[]? | select(.id == "groupingToMatrix") | .options | .rowField, .columnField]) as $matrix
  | ([.transformations[]? | select(.id == "filterFieldsByName") | .options.include.names // [] | .[]]) as $kept
  | ([.fieldConfig.overrides[]? | select(.matcher.id == "byName")
      | select(any(.properties[]; .id == "custom.hidden" and .value == true)) | .matcher.options]) as $hidden
  | if $matrix != [] then {ok: true, fields: $matrix}
    elif $kept != [] then {ok: true, fields: [$kept[] | select(IN($hidden[]) | not)]}
    else {ok: false, fields: []}
    end;

def offences($file):
  ([.templating.list[]? | {(.name): .type}] | add // {}) as $types
  | panels as $p
  | ($p.title // "") as $title
  | "\($file): panel \($title | tojson)" as $at
  # Text a person reads that may name a variable: titles, descriptions, a
  # text panel's content, legends and display names.
  | ([$p.title, $p.description, $p.options.content?, ($p.targets // [] | .[].legendFormat),
      ($p.fieldConfig.defaults.displayName?),
      ($p.fieldConfig.overrides[]?.properties[]? | select(.id == "displayName" or .id == "description") | .value)]
     | map(strings) | .[] | variables_shown[]
     | select(IN(.name; named_variables[]) | not)
     | select(.format != "text" or $types[.name] != "query")
     | "\($at) shows the variable \(.name)\(if .format then ":" + .format else "" end), whose value is not a name"),
    if $p.type == "row" then empty
    else
      (if ($p.description // "" | test("\\S")) then empty else "\($at) has no description" end),
      (if $title == exempt then empty else
        ($p.targets // [] | .[]
          | (.legendFormat // "") as $legend
          | ($legend | legend_labels[] | select(IN(human[]) | not)
              | "\($at) legend \($legend | tojson) shows the label \(.)"),
            (if $p.type != "table" and ($legend == "" or $legend == "__auto")
             then "\($at) query \(.refId) has no legend, so Grafana would name its series by every label"
             else empty end)),
        ([$p.fieldConfig.defaults?, ($p.fieldConfig.overrides[]?.properties[]?)]
          | .[] | objects
          | (if has("displayName") then .displayName elif .id? == "displayName" then .value else empty end)
          | strings | display_labels[] | select(IN(human[]) | not)
          | "\($at) display name shows the label \(.)"),
        ($p | picked_keys | "\($at) shows the field \(.)"),
        (if $p.type == "table" then
          ($p | shown_fields) as $shown
          | if $shown.ok | not then "\($at) is a table that keeps every label: give it a filterFieldsByName include list"
            else $shown.fields[] | select(value_field | not) | select(IN(human[]) | not)
              | "\($at) shows the column \(.)"
            end
         else empty end)
      end)
    end;

[inputs | {file: (input_filename | split("/") | last), dashboard: .}] as $all
| ([$all[] | .file as $file | .dashboard | offences($file)]
   + [$all | group_by(.dashboard.uid)[] | select(length > 1)
       | "uid \(.[0].dashboard.uid | tojson) is used by \(map(.file) | join(" and "))"]) as $offences
| if $offences != [] then error("\n" + ($offences | join("\n")))
  else $all[] | "\(.file): \(.dashboard.uid), \([.dashboard | panels | select(.type != "row")] | length) panels, every name a person reads"
  end
