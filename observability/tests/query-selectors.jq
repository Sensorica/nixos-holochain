# The series selectors a PromQL expression reads, as PromQL, with only their
# positive matchers kept: `holochain:dht_state{node="homelab"}` from
# `count(holochain:dht_state{node="homelab", conductor!=""} == 2) or vector(0)`.
#
# dashboardQueries requires each of them to select something, because a query
# can answer while reading nothing: `count(x == 1) or vector(0)` returns 0
# whether x is healthy or misspelt. Negative matchers are dropped since they
# keep every series whatever the label is called; vmTestGrafana checks that
# the labels they name exist.
#
# This is a reading of the dashboards' own PromQL, not a parser: it knows the
# grouping clauses, range selectors and offsets they use, and treats every
# other name not followed by "(" as a metric.
#
# Input: an array of {expr}. Output: the distinct selectors, sorted.

def keywords: ["and", "or", "unless", "bool", "offset", "by", "without", "on", "ignoring",
               "group_left", "group_right", "inf", "nan", "Inf", "NaN"];

def positive_matchers:
  [scan("([A-Za-z_][A-Za-z0-9_]*)\\s*(=~|!~|!=|=)\\s*(\"(?:[^\"\\\\]|\\\\.)*\")")
   | select(.[1] == "=" or .[1] == "=~") | "\(.[0])\(.[1])\(.[2])"];

def selectors:
  gsub("\\b(by|without|on|ignoring|group_left|group_right)\\s*\\([^)]*\\)"; " ")
  | gsub("\\[[^\\]]*\\]"; " ")
  | gsub("\\boffset\\s+[0-9]+[a-z]+"; " ")
  | [scan("(?<![A-Za-z0-9_:.\"])([A-Za-z_:][A-Za-z0-9_:]*)(?![A-Za-z0-9_:])\\s*(\\{(?:[^}\"]|\"(?:[^\"\\\\]|\\\\.)*\")*\\})?(?!\\s*\\()")
     | select(IN(.[0]; keywords[]) | not)
     | {name: .[0], matchers: ((.[1] // "") | positive_matchers)}
     | if .matchers == [] then .name else "\(.name){\(.matchers | join(", "))}" end];

[.[].expr | selectors[]] | unique
