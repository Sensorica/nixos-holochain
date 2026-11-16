# The publication guard (U4): the public repository stays public-safe.
# Called from nix/checks.nix with the per-system arguments of nix/shared.nix.
#
# It fails when a tracked file
#   - names Sensorica, in its content or its path (any case), other than
#     through the repository's own address (github.com/Sensorica/nixos-holochain,
#     github:Sensorica/nixos-holochain, sensorica.github.io/nixos-holochain),
#     which names where the project lives rather than the lab,
#   - holds an RFC 1918 address outside tests/,
#   - or sits under secrets/ without the .example suffix,
# and that finding is not listed in tests/public-guard-allowlist.txt.
# It also fails when the allowlist lists a finding that no longer exists, so
# the list can only shrink: an entry goes when its file is fixed or moved.
# The allowlist is empty once the fleet and the workshop leave the repository
# (AD3), and an empty allowlist is the v0.1.0 gate.
#
# Before scanning the tree, the guard runs itself on fixtures: a file holding
# only the repository's addresses must pass, and files naming a lab host, or
# the lab next to the repository's address, must fail.
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
  rfc='(^|[^0-9.])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)'
  # The repository's own addresses, exact; nothing else under Sensorica/ is exempt.
  repo='(github\.com[:/]|github:)Sensorica/nixos-holochain|sensorica\.github\.io/nixos-holochain'
  # The guard and its list name what they look for; nothing else is exempt.
  self_files=' (tests/public-guard[.]nix|tests/public-guard-allowlist[.]txt)$'

  # scan DIR ALLOWLIST OUT: list the findings under DIR, compare them with
  # ALLOWLIST, write the report to OUT, and return 1 on any new, stale or
  # secret finding.
  scan() {
    local dir=$1 allow=$2 out=$3 d
    d=$(mktemp -d)
    (
      cd "$dir"
      {
        grep -rIil sensorica . | while read -r f; do
          if sed -E "s#$repo##Ig" "$f" | grep -i sensorica > /dev/null; then
            echo "name ''${f#./}"
          fi
        done
        find . -type f -ipath '*sensorica*' | sed 's|^\./|name |'
        grep -rIlE "$rfc" --exclude-dir=tests . | sed 's|^\./|address |'
        find secrets -type f ! -name '*.example' 2>/dev/null | sed 's|^|secret |'
      } | { grep -vE "$self_files" || true; } | sort -u > "$d/found"
    )
    grep -vE '^[[:space:]]*(#|$)' "$allow" | sort -u > "$d/allowed" || true
    comm -23 "$d/found" "$d/allowed" > "$d/new"
    comm -13 "$d/found" "$d/allowed" > "$d/stale"
    grep '^secret ' "$d/found" > "$d/secrets" || true

    local status=0
    {
      if [ -s "$d/secrets" ]; then
        echo "Files under secrets/ that are not *.example (never allowlistable):"
        sed 's/^secret /  /' "$d/secrets"
        status=1
      fi
      if grep -qv '^secret ' "$d/new"; then
        echo "New findings, not in tests/public-guard-allowlist.txt:"
        grep -v '^secret ' "$d/new" | sed 's/^/  /'
        status=1
      fi
      if [ -s "$d/stale" ]; then
        echo "Allowlist entries that no longer match anything (remove them):"
        sed 's/^/  /' "$d/stale"
        status=1
      fi
      echo "public-guard: $(wc -l < "$d/found") findings, $(wc -l < "$d/allowed") allowlisted, $(wc -l < "$d/new") new, $(wc -l < "$d/stale") stale"
    } > "$out"
    return $status
  }

  # Self-test on fixtures, with an empty allowlist.
  : > "$w/empty"
  mkdir -p "$w/fx-repo" "$w/fx-host" "$w/fx-mixed"
  printf '%s\n' \
    'Source: https://github.com/Sensorica/nixos-holochain/blob/main/README.md' \
    'Input: github:Sensorica/nixos-holochain' \
    'Docs: https://sensorica.github.io/nixos-holochain/' > "$w/fx-repo/README.md"
  echo 'domain = "hs.sensorica.co";' > "$w/fx-host/host.nix"
  echo 'https://github.com/Sensorica/nixos-holochain, deployed at the Sensorica lab' > "$w/fx-mixed/notes.md"
  scan "$w/fx-repo" "$w/empty" "$w/r" || { echo "self-test: the repository's addresses alone must pass"; cat "$w/r"; exit 1; }
  if scan "$w/fx-host" "$w/empty" "$w/r"; then echo "self-test: hs.sensorica.co must fail"; exit 1; fi
  if scan "$w/fx-mixed" "$w/empty" "$w/r"; then echo "self-test: the lab beside the repository's address must fail"; exit 1; fi
  echo "public-guard self-test: repository addresses pass, a lab host fails, the lab beside an address fails"

  # The tree itself.
  scan ${self} ${./public-guard-allowlist.txt} "$w/report" && status=0 || status=1
  cat "$w/report"
  [ "$status" -eq 0 ] || exit 1
  touch $out
''
