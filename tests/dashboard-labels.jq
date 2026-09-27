# What a person can read on the provisioned dashboards, checked from their
# JSON: no label outside the human ones reaches a legend, a display name or a
# table column, every panel says what it answers, and no two dashboards share
# a uid. Prints one line per dashboard and fails, listing every offence, when
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

def panels: .panels[]? | ., (.panels // [])[];
# Every {{label}} in a legend and every ${__field.labels.label} or {{label}} in
# a display name.
def legend_labels: [scan("\\{\\{ *([A-Za-z_][A-Za-z0-9_]*) *\\}\\}") | .[0]];
def display_labels: legend_labels + [scan("__field\\.labels\\.([A-Za-z_][A-Za-z0-9_]*)") | .[0]]
  + [scan("__field\\.labels\\[\"([^\"]+)\"\\]") | .[0]];

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
  panels as $p
  | ($p.title // "") as $title
  | "\($file): panel \($title | tojson)" as $at
  | if $p.type == "row" then empty
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
