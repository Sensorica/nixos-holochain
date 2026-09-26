# Module options

Generated from the module declarations by `nix build .#options-doc`; do not edit by hand. CI fails when this file differs from a fresh build, so regenerate it in the same commit as any option change:

```bash
cp "$(nix build .#options-doc --print-out-paths)" docs/module-options.md
```

The prose about how the modules fit together lives in [`architecture.md`](architecture.md).

## services\.holochain-edgenode\.enable



Whether to enable Holochain edgenode (conductor + lair + hApp installer)\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.package



Holochain conductor package\. Its ` version ` selects the config schema the
module renders: below 0\.7 the network section carries ` bootstrap_url `,
` signal_url ` and ` relay_url `; from 0\.7 it carries ` bootstrap_url ` and
` relay_url `, because ` signal_url ` was removed from the schema\.



*Type:*
package



*Default:*
` inputs.holonix.packages.${pkgs.system}.holochain `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.adminPort

WebSocket port for the conductor admin interface (bound to localhost)\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*
` 4444 `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.allowedOrigins



Allowed origins for the admin and app WebSocket interfaces: ` * `, a single
origin, or a comma-separated list\. With ` * ` no ` --origin ` header is needed
on the admin call\.



*Type:*
string



*Default:*
` "*" `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.appPort



WebSocket port the hApp installer attaches as the app interface\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*
` 8888 `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.bootstrapUrl



Kitsune2 bootstrap server used for WAN peer discovery\. ` null ` selects the
default for the configured line: ` https://dev-test-bootstrap2.holochain.org `
below 0\.7 (Holo-Host/edgenode’s 0\.6\.1 template) and the same URL with a
trailing slash from 0\.7 (what ` holochain --create-config ` writes)\. No
production bootstrap URL is documented for either line, so point this at
your own infrastructure for a real deployment\.



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.conductorMetrics\.enable



Whether to enable a timer that exports the conductor’s own network stats as
` holochain_* ` series through node_exporter’s textfile collector\.

This is the fleet dashboard’s Holochain data source\. It calls
` dump-network-stats ` on the admin interface, which answers with
Kitsune2’s ` TransportStats ` on both the 0\.6 and 0\.7 lines, and derives
connection, byte and message gauges from it\. Requires
` metricsExporter.enable `
\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.conductorMetrics\.interval



How often the timer writes the textfile, as a systemd time span\. The
floor is what the dashboard’s resolution is worth: Prometheus scrapes
node_exporter on its own schedule and simply re-reads whatever the
file last said, so a value far above the scrape interval shows as a
staircase rather than a curve\.



*Type:*
string



*Default:*
` "30s" `



*Example:*
` "1min" `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.dataDir



Persistent state directory for the conductor database, the lair keystore
and the generated passphrase\. Created as the unit’s ` StateDirectory ` with
mode 0700\.

Keep it short\. The keystore’s unix socket is ` ${dataDir}/ks/socket ` and
unix socket paths are capped at 108 bytes (` SUN_LEN `); a deeper path makes
the conductor exit at startup with ` path must be shorter than SUN_LEN `\.



*Type:*
absolute path



*Default:*
` "/var/lib/holochain" `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.happs



hApps to install and keep enabled, keyed by installed app id\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

```
{
  dino-adventure = {
    src = pkgs.fetchurl {
      url = "https://github.com/holochain/dino-adventure/releases/download/v0.3.0/dino-adventure-v0.3.0.happ";
      sha256 = "...";
    };
    networkSeed = "workshop-2026";
  };
}

```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.happs\.\<name>\.installed



Whether to install and enable this hApp\.



*Type:*
boolean



*Default:*
` true `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.happs\.\<name>\.networkSeed



Network seed override for every DNA in this app\.



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.happs\.\<name>\.src



Path to the ` .happ ` bundle\. Fetch it by hash; never commit one (ADR-012)\.



*Type:*
absolute path

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.hcPackage



Holochain CLI package used by the hApp installer\. Keep it on the same
line as ` package `: the admin subcommand is ` hc client call ` from 0\.7 and
` hc sandbox call ` below it\.



*Type:*
package



*Default:*
` inputs.holonix.packages.${pkgs.system}.hc `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.installerTimeout



Seconds the hApp installer waits for the admin interface to answer before
failing\. The conductor needs about 80 seconds to open the port on an
unaccelerated VM, so leave room\.



*Type:*
signed integer



*Default:*
` 300 `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.metricsExporter\.enable



Whether to enable Prometheus node_exporter for fleet observability\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.metricsExporter\.port



Port to expose node metrics on\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*
` 9100 `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.metricsExporter\.textfileDirectory



Directory node_exporter’s textfile collector reads\. Every ` *.prom `
file in it is appended to ` /metrics ` verbatim, which is how metrics
that no exporter produces on its own reach Prometheus\.

The directory is created 0755 and owned by ` user `, so the conductor
metrics timer can write into it while node_exporter, which runs as
its own user, can read it\.



*Type:*
absolute path



*Default:*
` "/var/lib/prometheus-node-exporter-text-files" `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.openFirewall



Open firewall ports for the admin, app and metrics interfaces\. The
conductor binds its websockets to localhost, so this only matters for
the metrics exporter unless ` danger_bind_addr ` is configured by hand\.



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.passphraseFileName



Name of the lair passphrase file inside ` dataDir `\. Generated with mode
0600 on first boot if absent and reused on every boot after that, which
is what lets the keystore open again after a reboot with nobody present\.



*Type:*
string



*Default:*
` "lair-passphrase" `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.relayUrl



Iroh relay used when a direct connection cannot be established\. Required
by the conductor on both lines; ` null ` selects
` https://use1-1.relay.n0.iroh-canary.iroh.link./ `, the default both
0\.6\.3 and 0\.7\.0 write for themselves\.



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.signalUrl



WebRTC signal server\. Used only below 0\.7, where ` null ` selects
` wss://dev-test-bootstrap2.holochain.org `\. ` network.signal_url ` was
removed from the 0\.7 config schema, so from 0\.7 this option is ignored
and setting it raises a warning; use ` relayUrl ` instead\.



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.useSystemdNotify



Run the conductor as ` Type = "notify" `, so the unit becomes active only
once the conductor has signalled readiness rather than as soon as the
process exists\. Set to false to fall back to ` Type = "simple" `\.



*Type:*
boolean



*Default:*
` true `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.user



System user the conductor runs as\.



*Type:*
string



*Default:*
` "holochain" `

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-grafana\.enable



Whether to enable Prometheus + Grafana observability for Holochain fleet\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.adminPassword



Grafana administrator password\. The default is the workshop’s shared
password, kept as a default so a fleet works out of the box on a lab
network\.

It ends up world-readable in the Nix store, so it is a lab convenience
and not a secret\. On anything reachable from outside the lab, set this
to a value of your own, or drop the option and point
` services.grafana.settings.security.admin_password ` at a
` $__file{/run/secrets/...} ` reference instead\.



*Type:*
string



*Default:*
` "workshop2026" `

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.adminUser



Grafana administrator account\.



*Type:*
string



*Default:*
` "admin" `

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.dashboards



Directory of Grafana dashboard JSON files to provision\. Everything in
it is loaded at startup and re-read every 30 seconds\. The module ships
` holochain-fleet.json ` (uid ` holochain-fleet `), which draws CPU, memory
and host network from node_exporter and the conductor’s own
` holochain_* ` series from the edgenode module’s metrics timer\.



*Type:*
absolute path



*Default:*
` ./dashboards `

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.grafanaPort



Port Grafana listens on\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*
` 3000 `

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.openFirewall



Open firewall ports for Grafana, Prometheus, and node_exporter\.



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.prometheusPort



Port Prometheus listens on\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*
` 9090 `

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.scrapeInterval



How often Prometheus scrapes its targets\. Prometheus itself defaults to
one minute, which for a lab fleet of a handful of nodes draws a
fifteen-minute window as about fifteen points, and makes ` rate() ` over
a short range flat or empty\. The conductor metrics timer writes every
30 s by default, so this is deliberately below it\.



*Type:*
string



*Default:*
` "15s" `

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.scrapeTargets



Prometheus node_exporter targets across the fleet (host:port)\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[ "edgenode-01:9100" "edgenode-02:9100" "edgenode-03:9100"
  "edgenode-04:9100" "edgenode-05:9100" ]

```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-http-gateway\.enable



Whether to enable the Holochain HTTP gateway in front of the local conductor\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.package



The ` hc-http-gw ` package to run\. The default is built from the tagged
upstream source for the Holochain line the conductor runs, so it does
not have to be set by hand when the conductor’s line changes\.



*Type:*
package



*Default:*
the ` hc-http-gw ` release matching ` services.holochain-edgenode.package.version `: 0\.4\.x for Holochain 0\.7, 0\.3\.x for 0\.6

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.address



Address the gateway binds to, passed as ` --address ` (` HC_GW_ADDRESS `)\.
The default keeps it on loopback; set it to ` 0.0.0.0 ` and turn on
` services.holochain-http-gateway.openFirewall ` to serve a LAN\.



*Type:*
string



*Default:*
` "127.0.0.1" `

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.adminPort



Admin websocket port of the conductor the gateway drives\. It becomes
` HC_GW_ADMIN_WS_URL=ws://127.0.0.1:<adminPort> `, which the binary
requires: without it the process exits immediately\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*
` config.services.holochain-edgenode.adminPort `

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.allowedAppIds



Installed app ids the gateway is allowed to reach, joined into
` HC_GW_ALLOWED_APP_IDS `\. Empty, the default, exposes nothing: the
gateway runs and refuses every zome-call path\. Each id listed here
needs a matching entry in
` services.holochain-http-gateway.allowedFns `\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[
  "dino-adventure"
]
```

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.allowedFns



Per app id, the zome functions the gateway may call, written
` zome_name/fn_name `\. Each entry becomes
` HC_GW_ALLOWED_FNS_<app-id> `, a comma separated list\.

The single-element list ` ["*"] ` allows every function in every zome of
that app, which the binary accepts but which also exposes the app’s
writes, since the gateway does nothing else to tell a read from a
write\. Using it raises an evaluation warning\. ` * ` cannot be mixed with
named functions; the binary would fail to parse the value\.



*Type:*
attribute set of list of string



*Default:*
` { } `



*Example:*

```
{
  dino-adventure = ["dino_adventure/get_all_dinos_local"];
  my-app = ["*"];
}

```

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.maxAppConnections



How many app websocket connections the gateway keeps open at once, one
per allowed app, as ` HC_GW_MAX_APP_CONNECTIONS `\. Older connections are
closed when the limit is reached\.



*Type:*
unsigned integer, meaning >=0



*Default:*
` 50 `

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.openFirewall



Open ` services.holochain-http-gateway.port ` in the firewall\.
Leave it off unless the gateway is meant to be reachable from other
machines; the conductor’s admin interface is reachable through
anything the gateway is allowed to call\.



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.payloadLimitBytes



Largest accepted ` payload ` query parameter, in bytes, as
` HC_GW_PAYLOAD_LIMIT_BYTES `\. Measured on the base64 text before it is
decoded, so it is really a cap on the URL length the gateway will
process\. Upstream’s own default is the same 10 KiB\.



*Type:*
unsigned integer, meaning >=0



*Default:*
` 10240 `

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.port



Port the gateway listens on, passed as ` --port ` (` HC_GW_PORT `)\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*
` 8090 `

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.zomeCallTimeoutMs



Deadline for a single zome call, in milliseconds, as
` HC_GW_ZOME_CALL_TIMEOUT_MS `\. A call that outruns it answers 500\.



*Type:*
unsigned integer, meaning >=0



*Default:*
` 10000 `

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-windtunnel\.enable



Donate this machine to the Holochain Foundation’s Wind Tunnel test
network\.

The container runs its own Holochain conductor and reports to the
Foundation’s Nomad cluster at ` nomad-server-01.holochain.org `; the
runner’s own README calls these machines “designed to be for internal
use only” and warns that the image “requires extensive permissions on
the host machine that are effectively root access” and “should only be
run on a dedicated machine”\.

Enabling this donates the machine\. It does not feed the fleet
dashboard: the ` holochain_* ` series come from
` services.holochain-edgenode.conductorMetrics `, and nothing in this
module exposes a Prometheus endpoint\. Off by default, deliberately\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [modules/holochain-windtunnel\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-windtunnel.nix)



## services\.holochain-windtunnel\.autoStart



Start the container at boot\. Set to false to keep the unit generated
but idle, which is what the VM test does: the test sandbox has no
network, so the image cannot be pulled there\.



*Type:*
boolean



*Default:*
` true `

*Declared by:*
 - [modules/holochain-windtunnel\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-windtunnel.nix)



## services\.holochain-windtunnel\.backend



OCI backend used to run the container\. Podman is the default: it needs
no daemon and the NixOS module wires the unit to it directly\. The
runner’s README documents Docker, and the image is indifferent to
which one starts it\.



*Type:*
one of “podman”, “docker”



*Default:*
` "podman" `

*Declared by:*
 - [modules/holochain-windtunnel\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-windtunnel.nix)



## services\.holochain-windtunnel\.extraOptions



Flags passed to ` podman run ` / ` docker run `\. The default is the set the
runner’s README requires: host networking, privileged, and the host
cgroup namespace, so the Nomad agent inside can schedule and supervise
its own workloads\. Removing any of them stops the runner from working;
they are an option only so that a host with a conflicting device or
network setup can adjust them knowingly\.



*Type:*
list of string



*Default:*

```
[
  "--net=host"
  "--privileged"
  "--cgroupns=host"
]
```

*Declared by:*
 - [modules/holochain-windtunnel\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-windtunnel.nix)



## services\.holochain-windtunnel\.hostname



Hostname the container reports to the Nomad cluster, passed as
` --hostname `\. The runner’s README asks for a unique, recognisable
` nomad-client-<user> ` style name, since it is how the machine is
identified in the Nomad and Tailscale dashboards\.



*Type:*
string



*Default:*
` "nomad-client-${config.networking.hostName}" `

*Declared by:*
 - [modules/holochain-windtunnel\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-windtunnel.nix)



## services\.holochain-windtunnel\.image



Runner image, pinned by digest\.

` ghcr.io/holochain/wind-tunnel-runner ` publishes only the moving tags
` latest `, ` latest-amd64 ` and ` latest-arm64 `, so a tag pin would silently
change what a fleet runs\. The default is the multi-architecture index
digest that ` latest ` resolved to on 2026-08-28, which keeps ` amd64 ` and
` arm64 ` hosts on the same pin\. Re-pin with

skopeo inspect docker://ghcr\.io/holochain/wind-tunnel-runner:latest



*Type:*
string



*Default:*
` "ghcr.io/holochain/wind-tunnel-runner@sha256:650c91806275681bc1961e0e55e85fa7fbf31bebe0c8665fc0a6af71ac330fa2" `

*Declared by:*
 - [modules/holochain-windtunnel\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-windtunnel.nix)


