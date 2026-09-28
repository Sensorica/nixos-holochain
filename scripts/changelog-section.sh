#!/bin/sh
# Print the body of one version's section of CHANGELOG.md: everything under
# its "## [VERSION]" heading up to the next "## [" heading or the link
# references at the foot of the file, with leading and trailing blank lines
# trimmed. The release workflow publishes this text as the GitHub release note.
#
# Usage: scripts/changelog-section.sh VERSION [CHANGELOG]
#   VERSION is written as in the heading, without the tag's "v":
#   0.1.0, 0.1.0-rc.1, or Unreleased.
#
# Exits 1, naming the reason on stderr, when the file cannot be read or the
# section is missing or empty, so a tag without release notes publishes nothing.
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "$1" ]; then
  echo "usage: $0 VERSION [CHANGELOG]" >&2
  exit 2
fi

version=$1
file=${2:-CHANGELOG.md}

if [ ! -r "$file" ]; then
  echo "$0: cannot read $file" >&2
  exit 1
fi

# The heading is matched as a literal prefix, so the dots in a version are not
# regex wildcards, and the closing bracket keeps [0.1.0] from matching
# [0.1.0-rc.1]. After the bracket only the end of the line or the Keep a
# Changelog " - DATE" suffix is accepted.
#
# A carriage return is dropped from every line, so a CRLF file reads like an LF
# one, and trailing blanks after a heading are ignored. Inside a fenced code
# block (``` or ~~~) a line starting "## [" or "[x]: " is content, not the end
# of the section.
notes=$(awk -v heading="## [$version]" '
  { sub(/\r$/, "") }
  !found && index($0, heading) == 1 {
    rest = substr($0, length(heading) + 1)
    sub(/[[:space:]]+$/, "", rest)
    if (rest == "" || rest ~ /^ - /) { found = 1; next }
  }
  found && !fence && /^## \[/ { exit }
  found && !fence && /^\[[^]]+\]: / { exit }
  found && /^ ? ? ?(```|~~~)/ { fence = !fence }
  found && !fence && /^[[:space:]]*$/ { blanks++; next }
  found {
    if (started) { while (blanks > 0) { print ""; blanks-- } }
    blanks = 0
    started = 1
    print
  }
' "$file")

if [ -z "$notes" ]; then
  echo "$0: no section \"## [$version]\" with content in $file" >&2
  exit 1
fi

printf '%s\n' "$notes"
