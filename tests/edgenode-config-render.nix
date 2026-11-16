# Called from nix/checks.nix with the per-system arguments of
# nix/shared.nix.
# The #54 passthroughs, rendered on both lines and then handed to
# that line's real conductor, which rejects unknown keys and bad
# values: "Conductor ready." is the proof each rendered key is one
# the conductor accepts, not merely one the module writes. No VM
# and no network needed; the bootstrap and relay URLs are never
# reached before readiness.
{
  edgenodeNode,
  inputs,
  on06,
  pkgs,
  system,
  ...
}: let
  render = extra:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        edgenodeNode
        extra
        {
          services.holochain-edgenode = {
            enable = true;
            bootstrapUrl = "http://bootstrap.invalid";
            relayUrl = "http://bootstrap.invalid/relay";
            relayAllowPlainText = true;
            requestTimeoutS = 90;
            dbSyncLevel = "Off";
            wasmBackend = "cranelift";
          };
        }
      ];
    })
    .config
    .services
    .holochain-edgenode;
  e07 = render {};
  e06 = render on06;
in
  pkgs.runCommand "edgenode-config-render" {} ''
    has() {
      grep -qxF -- "$2" "$1" || { echo "missing from $1: $2"; cat "$1"; exit 1; }
    }
    lacks() {
      if grep -q -- "$2" "$1"; then echo "unexpected in $1: $2"; cat "$1"; exit 1; fi
    }

    for cfg in ${e07.conductorConfigFile} ${e06.conductorConfigFile}; do
      has "$cfg" '  relay_url: http://bootstrap.invalid/relay'
      has "$cfg" '  request_timeout_s: 90'
      has "$cfg" '  advanced: {"irohTransport":{"relayAllowPlainText":true}}'
    done
    has ${e07.conductorConfigFile} 'db_sync_level: Off'
    has ${e07.conductorConfigFile} 'wasm_backend: cranelift'
    # Below 0.7 both keys are unknown to the conductor.
    lacks ${e06.conductorConfigFile} 'db_sync_level'
    lacks ${e06.conductorConfigFile} 'wasm_backend'

    # Each line's conductor on its own rendered config. The data root
    # moves under the build directory, whose path is short enough
    # for lair's unix socket.
    ready() {
      name=$1 conductor=$2 cfg=$3
      mkdir -p "$TMPDIR/$name"
      sed "s|/var/lib/holochain|$TMPDIR/$name|g" "$cfg" > "$name.yaml"
      echo pass | "$conductor" --piped -c "$name.yaml" > "$name.log" 2>&1 &
      pid=$!
      for _ in $(seq 1 120); do
        if grep -q "Conductor ready" "$name.log"; then
          echo "$name: Conductor ready"
          kill "$pid"
          wait "$pid" || true
          return 0
        fi
        sleep 1
      done
      echo "$name: the conductor never became ready on its rendered config"
      cat "$name.yaml" "$name.log"
      exit 1
    }
    ready h07 ${pkgs.lib.getExe' e07.package "holochain"} ${e07.conductorConfigFile}
    ready h06 ${pkgs.lib.getExe' e06.package "holochain"} ${e06.conductorConfigFile}
    touch $out
  ''
