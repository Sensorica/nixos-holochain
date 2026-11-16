# The publication guard (U4): the public repository stays public-safe.
# Called from nix/checks.nix with the per-system arguments of nix/shared.nix.
#
# It fails when a tracked file
#   - names Sensorica, in its content or its path (any case),
#   - holds an RFC 1918 address outside tests/,
#   - or sits under secrets/ without the .example suffix,
# and that finding is not listed in tests/public-guard-allowlist.txt.
# It also fails when the allowlist lists a finding that no longer exists, so
# the list can only shrink: an entry goes when its file is fixed or moved.
# The allowlist is empty once the fleet and the workshop leave the repository
# (AD3), and an empty allowlist is the v0.1.0 gate.
#
# The flake source holds only tracked files, so an untracked or ignored file
# (a real secret in secrets/, say) is never seen here, by construction.
{
  pkgs,
  self,
  ...
}:
pkgs.runCommand "public-guard" {
  nativeBuildInputs = [pkgs.gnugrep pkgs.findutils pkgs.coreutils pkgs.gnused];
} ''
  w=$(mktemp -d)
  cd ${self}
  allow=${./public-guard-allowlist.txt}
  rfc='(^|[^0-9.])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)'
  # The guard and its list name what they look for; nothing else is exempt.
  self_files=' (tests/public-guard[.]nix|tests/public-guard-allowlist[.]txt)$'

  {
    grep -rIil sensorica . | sed 's|^\./|name |'
    find . -type f -ipath '*sensorica*' | sed 's|^\./|name |'
    grep -rIlE "$rfc" --exclude-dir=tests . | sed 's|^\./|address |'
    find secrets -type f ! -name '*.example' 2>/dev/null | sed 's|^|secret |'
  } | grep -vE "$self_files" | sort -u > "$w/found"

  grep -vE '^[[:space:]]*(#|$)' "$allow" | sort -u > "$w/allowed" || true

  comm -23 "$w/found" "$w/allowed" > "$w/new"
  comm -13 "$w/found" "$w/allowed" > "$w/stale"
  grep '^secret ' "$w/found" > "$w/secrets" || true

  status=0
  if [ -s "$w/secrets" ]; then
    echo "Files under secrets/ that are not *.example (never allowlistable):"
    sed 's/^secret /  /' "$w/secrets"
    status=1
  fi
  if grep -qv '^secret ' "$w/new"; then
    echo "New findings, not in tests/public-guard-allowlist.txt:"
    grep -v '^secret ' "$w/new" | sed 's/^/  /'
    status=1
  fi
  if [ -s "$w/stale" ]; then
    echo "Allowlist entries that no longer match anything (remove them):"
    sed 's/^/  /' "$w/stale"
    status=1
  fi
  echo "public-guard: $(wc -l < "$w/found") findings, $(wc -l < "$w/allowed") allowlisted, $(wc -l < "$w/new") new, $(wc -l < "$w/stale") stale"
  [ "$status" -eq 0 ] || exit 1
  touch $out
''
