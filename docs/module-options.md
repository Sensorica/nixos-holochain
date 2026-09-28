# Module options

Generated from the module declarations by `nix build .#options-doc`; do not edit by hand. CI fails when this file differs from a fresh build, so regenerate it in the same commit as any option change:

```bash
cp "$(nix build .#options-doc --print-out-paths)" docs/module-options.md
```

The prose about how the modules fit together lives in [`architecture.md`](architecture.md).

## services\.holochain-bootstrap\.enable

Whether to enable the Kitsune2 bootstrap and relay server (` kitsune2-bootstrap-srv `)\.

One process serves peer discovery at ` /bootstrap/{space} ` and an iroh
relay at ` /relay ` on the same port\. Point conductors at it with
` services.holochain-edgenode.bootstrapUrl = "http(s)://<host>:<port>" `
and ` relayUrl = "http(s)://<host>:<port>/relay" `\.

The relay is open: it has no authentication by default, so anyone who
can reach the port can relay traffic through it\. Keep it on a LAN or
behind a firewall unless that is what you want\. Its state is ephemeral
and cannot be shared between instances, so run one server per network,
not several behind a load balancer
\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.package



The ` kitsune2-bootstrap-srv ` package\. The flake’s module defaults it to
the holonix main-0\.6 build (kitsune2 0\.4\.1), the line the Sensorica
fleet runs\. A 0\.7 network takes ` nixos-holochain.packages.${system}.bootstrap-srv `
instead (kitsune2 0\.5\.0): keep the server on the same line as the
conductors that use it\.



*Type:*
package



*Default:*

```nix
nixos-holochain.packages.${system}.bootstrap-srv-0_6
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.extraArgs



Further ` kitsune2-bootstrap-srv ` flags, appended as given\.



*Type:*
list of string



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "--max-entries-per-space"
  "64"
  "--allowed-origins"
  "https://example.org"
]
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.listenAddresses



Addresses the HTTP server binds, each on ` port `\. IPv6 addresses go in
brackets\. The default ` [::] ` is dual-stack on Linux and accepts IPv4
as well; on a host with IPv6 disabled, use ` 0.0.0.0 `\.

Do not list both ` 0.0.0.0 ` and ` [::] `, although that is the server’s
own production default\. On Linux the second bind fails with “address
in use”, and the 0\.4\.1 server does not exit on a failed bind: it logs
nothing, listens on nothing and stays up, so systemd reports the unit
active\. Seen in this repository’s VM test, not guessed\.



*Type:*
list of string



*Default:*

```nix
[
  "[::]"
]
```



*Example:*

```nix
[
  "192.168.1.10"
]
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.logLevel



` RUST_LOG ` filter for the server\. Its built-in default is ` debug `,
which logs every request to the journal\.



*Type:*
string



*Default:*

```nix
"info"
```



*Example:*

```nix
"info,kitsune2_bootstrap_srv=debug"
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.openFirewall



Open ` port ` on TCP and ` quicPort ` on UDP\. Conductors on other machines
cannot reach the server without this or an equivalent firewall rule\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.port



TCP port for bootstrap and relay, over HTTPS when a certificate is
configured and plain HTTP otherwise\. The unit holds
` CAP_NET_BIND_SERVICE ` so a port below 1024 works without root\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
443
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.quicAddress



Address the QUIC address discovery (QAD) endpoint binds, which lets
iroh clients learn their public address\. On Linux ` [::] ` also accepts
IPv4\.



*Type:*
string



*Default:*

```nix
"[::]"
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.quicPort



UDP port for QUIC address discovery; 7842 is iroh’s default\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
7842
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.tlsCertFile



PEM certificate for HTTPS and for QUIC\. A path as a string, read at
service start through systemd’s ` LoadCredential `, so it never enters
the Nix store and may be readable by root only\. Set it together with
` tlsKeyFile `\.

Without it the server speaks plain HTTP, and QUIC uses a self-signed
certificate it generates at start\. That is enough for a LAN of
edgenodes, which then need
` services.holochain-edgenode.relayAllowPlainText = true `\. It is not
enough for a packaged Moss desktop: Moss enables plain-text relays only
in development builds, so a laptop running stock Moss needs this server
on HTTPS with a certificate it trusts\.

The certificate is read once, at start: restart the unit after a
renewal\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"/var/lib/acme/bootstrap.example.org/fullchain.pem"
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.tlsKeyFile



PEM private key matching ` tlsCertFile `, loaded the same way\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"/var/lib/acme/bootstrap.example.org/key.pem"
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-bootstrap\.workerThreads



Worker threads for the HTTP server\. ` null ` keeps the server’s
production default, four per CPU\. The workers block on file IO, which
is why the default exceeds the core count\.



*Type:*
null or (positive integer, meaning >0)



*Default:*

```nix
null
```

*Declared by:*
 - [modules/holochain-bootstrap\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-bootstrap.nix)



## services\.holochain-edgenode\.enable



Whether to enable Holochain edgenode (conductor + lair + hApp installer)\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

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

```nix
inputs.holonix.packages.${pkgs.stdenv.hostPlatform.system}.holochain
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.adminAllowedOrigins



Allowed origins for the admin WebSocket interface\. The default is the
Origin header ` hc ` sends when given no ` --origin `, which is what the
hApp installer and the metrics timer use, and which no browser sends:
with ` * ` any web page open in a browser on the node could drive the
admin API over ` ws://localhost `\. Widen it only for an admin UI you
trust\.



*Type:*
string



*Default:*

```nix
"holochain_websocket"
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.adminPort



WebSocket port for the conductor admin interface (bound to localhost)\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
4444
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.allowedOrigins



Allowed origins for the app WebSocket interface the installer attaches:
` * `, a single origin, or a comma-separated list\.



*Type:*
string



*Default:*

```nix
"*"
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.appPort



WebSocket port the hApp installer attaches as the app interface\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
8888
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.binaryCache\.enable



Declare the Holochain Foundation’s binary cache
(` https://holochain-ci.cachix.org `) in the host’s ` nix.settings `, so
` holochain ` and ` hc ` are downloaded prebuilt instead of compiled from
source\. A flake’s own ` nixConfig ` does not reach a downstream flake
that imports this module, and without the cache a first
` nixos-rebuild switch ` compiles the whole Holochain workspace
(seen on a homelab rehearsal, 2026-09-26)\.

The setting lands in ` nix.conf ` only once a switch has activated it,
so the very first switch that brings it still builds from source
unless it is run with
` --option extra-substituters https://holochain-ci.cachix.org --option extra-trusted-public-keys <key> `; see docs/deployment\.md\.



*Type:*
boolean



*Default:*

```nix
true
```

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

```nix
null
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.conductorMetrics\.enable



Whether to enable a timer that exports the conductor’s own network stats as
` holochain_* ` series through node_exporter’s textfile collector\.

This is the fleet dashboard’s Holochain data source\. It calls
` dump-network-stats ` on the admin interface, which answers with
Kitsune2’s ` TransportStats ` on both the 0\.6 and 0\.7 lines, and derives
connection gauges and byte and message counters from it; it also
counts installed apps by status from ` list-apps `\. The counters are
running totals kept in ` conductor-metrics-counters.json ` under
` dataDir `, so a peer disconnecting does not pull them down\. It also
calls ` dump-network-metrics --include-dht-summary ` and writes one
` holochain_dht_* ` series set per DHT the conductor is in (peers, ops
held here and by the best peer, pending fetches, seconds since the
last gossip, completed rounds and timeouts), labelled ` app_id `,
` role ` and ` dna `, and names every app and DHT in ` holochain_app_info `
and ` holochain_dht_info ` from ` displayName ` and ` roleNames `\. Every
line carries ` conductor `, from ` name `\. Requires
` metricsExporter.enable `
\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

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

```nix
"30s"
```



*Example:*

```nix
"1min"
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.conductorMetrics\.name



The ` conductor ` label on every ` holochain_* ` series this node
writes, and the name dashboards show for the conductor\. It keeps
two conductors on one machine apart (this one and a Moss node, say),
so give each its own\.



*Type:*
string



*Default:*

```nix
"Holochain"
```



*Example:*

```nix
"Workshop"
```

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

```nix
"/var/lib/holochain"
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.dbSyncLevel



` db_sync_level `, the SQLite synchronous level, from 0\.7 only (0\.6 has
` db_sync_strategy ` instead, which this module does not set)\. ` null `
leaves the conductor default, ` Normal `\. ` Off ` trades crash safety for
speed\. Ignored with a warning below 0\.7\.



*Type:*
null or one of “Full”, “Normal”, “Off”



*Default:*

```nix
null
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.happs



hApps to install and keep enabled, keyed by installed app id\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
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



## services\.holochain-edgenode\.happs\.\<name>\.displayName



What dashboards call this app, as ` app_name ` on the
` holochain_app_info ` and ` holochain_dht_info ` series\. ` null `
falls back to the bundle’s own name from ` list-apps `, with
underscores and dashes read as spaces and the first letter
capitalised (` requests_and_offers ` reads “Requests and
offers”)\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"Requests & Offers"
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.happs\.\<name>\.installed



Whether to install this hApp when absent and keep it enabled\.
Setting it to false (or removing the entry) stops managing the
app; it does not disable or uninstall an app already installed\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.happs\.\<name>\.networkSeed



Network seed override for every DNA in this app\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.happs\.\<name>\.roleNames



What dashboards call each part of this app, keyed by DNA role,
as ` part_name ` on ` holochain_dht_info `\. A role left out reads
as nothing when the app has one role, so its network is shown
by the app’s name alone, and otherwise as the role id with a
one-letter prefix dropped and underscores read as spaces
(` rFiles ` reads “Files”)\.



*Type:*
attribute set of string



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  hrea = "Accounting";
  requests_and_offers = "Listings";
}
```

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

```nix
inputs.holonix.packages.${pkgs.stdenv.hostPlatform.system}.hc
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.installerTimeout



Seconds the hApp installer allows each of its waits: the admin interface
answering at all, then, per hApp, the install and the enable settling\.
The conductor needs about 80 seconds to open the port on an
unaccelerated VM, so leave room\. The unit itself has no start timeout,
so raising this is enough\.



*Type:*
signed integer



*Default:*

```nix
300
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.metricsExporter\.enable



Whether to enable Prometheus node_exporter for fleet observability\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.metricsExporter\.port



Port to expose node metrics on\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
9100
```

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

```nix
"/var/lib/prometheus-node-exporter-text-files"
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.openFirewall



Open firewall ports for the app and metrics interfaces\. The admin port
is never opened\. The conductor binds its websockets to localhost, so in
practice this matters for the metrics exporter, and for the app port
only if ` danger_bind_addr ` is configured by hand\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.passphraseFileName



Name of the lair passphrase file inside ` dataDir `\. Generated with mode
0600 on first boot if absent and reused on every boot after that, which
is what lets the keystore open again after a reboot with nobody present\.



*Type:*
string



*Default:*

```nix
"lair-passphrase"
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.relayAllowPlainText



Let the iroh transport use a plain-HTTP relay, by rendering
` network.advanced.irohTransport.relayAllowPlainText: true `\. Kitsune2
refuses an ` http:// ` relay URL without it, so the conductor would not
start\. Needed for a LAN ` services.holochain-bootstrap ` server without
TLS; leave it off for an ` https:// ` relay\. Works on both lines\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.relayUrl



Iroh relay used when a direct connection cannot be established\. Required
by the conductor on both lines; ` null ` selects
` https://use1-1.relay.n0.iroh-canary.iroh.link./ `, the default both
0\.6\.3 and 0\.7\.0 write for themselves\.

For a ` services.holochain-bootstrap ` server this is
` http(s)://<host>:<port>/relay `: the same server as ` bootstrapUrl `,
on the ` /relay ` path\. A plain ` http:// ` relay also needs
` relayAllowPlainText `\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.requestTimeoutS



` network.request_timeout_s `: seconds before a request and its response
time out\. ` null ` leaves the conductor default, 60\. Same key on both
lines\.



*Type:*
null or (positive integer, meaning >0)



*Default:*

```nix
null
```



*Example:*

```nix
90
```

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

```nix
null
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.useSystemdNotify



Run the conductor as ` Type = "notify" `, so the unit becomes active only
once the conductor has signalled readiness rather than as soon as the
process exists\. Set to false to fall back to ` Type = "simple" `\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.user



System user the conductor runs as\.



*Type:*
string



*Default:*

```nix
"holochain"
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-edgenode\.wasmBackend



` wasm_backend `, from 0\.7 only: which compiler runs zomes when the
Holochain binary was built with more than one\. The conductor refuses a
backend it was not built with\. ` null ` uses whichever is available\.
Ignored with a warning below 0\.7\.



*Type:*
null or one of “cranelift”, “LLVM”, “wasmi”



*Default:*

```nix
null
```

*Declared by:*
 - [modules/holochain-edgenode\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-edgenode.nix)



## services\.holochain-grafana\.enable



Whether to enable Prometheus + Grafana observability for Holochain fleet\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.adminPassword



Grafana administrator password\. The default is the workshop’s shared
password, kept as a default so a fleet works out of the box on a lab
network\.

It ends up world-readable in the Nix store, so it is a lab convenience
and not a secret, and nixpkgs warns about it on every evaluation\. On
anything reachable from outside the lab use ` adminPasswordFile `, which
takes precedence over this option\.



*Type:*
string



*Default:*

```nix
"workshop2026"
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.adminPasswordFile



Path on the target machine to a file holding the Grafana administrator
password\. When set it takes precedence over ` adminPassword `, and the
password never enters the Nix store: systemd hands the file to Grafana
as a credential (` LoadCredential `), and Grafana reads it through a
` $__file{...} ` reference\.

Because systemd reads it, the file can stay owned by root with mode
0400, and it can be created before Grafana (or its user) exists\.
Create it on the node before the first deploy, for example:

```
sudo install -d -m 0700 /var/lib/secrets
sudo install -m 0400 /dev/null /var/lib/secrets/grafana-admin-password
printf '%s' 'the-password' | sudo tee /var/lib/secrets/grafana-admin-password > /dev/null
```

If the file is missing, grafana\.service fails to start and its journal
names the path\.

The path must survive a reboot, so ` /run ` is the wrong place for it
unless a secrets manager repopulates it at boot\.



*Type:*
null or absolute path not in the Nix store



*Default:*

```nix
null
```



*Example:*

```nix
"/var/lib/secrets/grafana-admin-password"
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.adminUser



Grafana administrator account\.



*Type:*
string



*Default:*

```nix
"admin"
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.dashboards



Directory of Grafana dashboard JSON files to provision\. Everything in
it is loaded at startup and re-read every 30 seconds\. The module ships
` holochain-fleet.json ` (uid ` holochain-fleet `): an Overview row saying
per node whether the node, its conductor and its services are up, a
Holochain row drawn from the edgenode module’s metrics timer, and a
Host health row drawn from node_exporter\.

A directory in the Nix store (a path in your flake, or a directory
inside a flake input or package such as ` "${inputs.x}/dashboards" `)
has every dashboard’s ` units ` textbox variable set from
` overviewUnits ` on its way in, every field override matched by name
to ` name ` given the units’ names as value mappings, and the
` room_app `, ` room_part ` and ` room_label ` constants set from ` room `
when that is set\. A directory outside the store, or a
store path written as a bare string that carries no Nix string
context, is provisioned as it is\.



*Type:*
absolute path



*Default:*

```nix
./dashboards
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.grafanaPort



Port Grafana listens on\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
3000
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.openFirewall



Open firewall ports for Grafana, Prometheus, and node_exporter\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.overviewUnits



systemd units the dashboards watch on every node, read from
node_exporter’s systemd collector (` node_systemd_unit_state `), each
with the name a person reads for it\. The keys are units, the values
their names; a unit whose name is null, or an entry of a plain list of
units, is shown by its unit name\.

The default covers the long-running units the nixos-holochain modules
create, plus the services a fleet node usually runs beside them\. It
holds only units that stay active while all is well: long-running
services, timers, sockets, and the app installer, a one-shot that
remains active once it has run\. Two one-shot helpers are left out:
` holochain-conductor-metrics.service ` sits idle between runs, so its
timer is listed instead, and ` grafana-secret-key.service ` runs once at
boot; if either fails, the Fleet status panel counts it\. The Nix
daemon is listed by its socket: NixOS starts ` nix-daemon.service ` on
demand, so the service is inactive on an idle node that is perfectly
healthy\.

The names reach a dashboard as value mappings: every field override
matched by name to ` name ` (the unit label) in a provisioned dashboard
gets one regex mapping per named unit\.

The fleet dashboard’s Services panel has one row per node and one
column per unit that some selected node has\. A unit one node runs and
another does not shows as absent on the second node’s row; a unit no
selected node runs has no column at all, so one set serves a whole
fleet whose machines run different things\.

Each key is a regular expression Prometheus matches against the whole
unit name, suffix included, so ` restic-backups-.* ` works, and its name
is given to every unit it matches\. The keys are joined with ` | ` into
the default of the dashboard’s ` units ` variable; a viewer can type
another regex in the browser, which lives in that page’s URL and is
never saved to the dashboard\.

Setting this option replaces the default\. To add a unit and keep the
defaults, define it with ` lib.mkOptionDefault `, which merges with the
default instead of overriding it:
` overviewUnits = lib.mkOptionDefault { "caddy.service" = "Web server"; }; `
(a list, ` lib.mkOptionDefault [ "caddy.service" ] `, merges the same
way)\.

This only picks what the Services panel draws\. The Fleet status panel
counts every failed unit on the node whatever is listed here, except
device, scope and slice units, which the node_exporter flags these
modules set leave out, and the ` holochain:node_problem ` rule gives
each failed unit a sentence of its own, naming it by its name here or,
when it has none or is not listed, by its unit name\.



*Type:*
(attribute set of (null or string)) or (list of string) convertible to it



*Default:*

```nix
{
  "(podman|docker)-wind-tunnel-runner.service" = "Wind Tunnel runner";
  "grafana.service" = "Dashboards";
  "holochain-conductor-metrics.timer" = "Holochain readings (timer)";
  "holochain-conductor.service" = "Holochain conductor";
  "holochain-happ-installer.service" = "App installer";
  "holochain-http-gateway.service" = "HTTP gateway";
  "nix-daemon.socket" = "Nix";
  "prometheus-node-exporter.service" = "Machine readings";
  "prometheus.service" = "Metrics database";
  "sshd.service" = "Remote login";
  "tailscaled.service" = "Private network (Tailscale)";
}
```



*Example:*

```nix
{
  "holochain-conductor.service" = "Holochain conductor";
  "caddy.service" = "Web server";
  "restic-backups-.*" = "Backups";
}

```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.prometheusPort



Port Prometheus listens on\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
9090
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.room



The one app part a room screen follows writes in\. Rendered into the
constant variables ` room_app `, ` room_part ` and ` room_label ` of every
provisioned dashboard that declares them; when null, those variables
keep the defaults their dashboard gives them\.

An app installed by hand in Moss is not a good choice: its id changes
with every installation and holds ` $ `, which Grafana reads as a
variable\.



*Type:*
null or (submodule)



*Default:*

```nix
null
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.room\.app



The installed_app_id of an app this module’s fleet installs from Nix\.



*Type:*
string



*Example:*

```nix
"requests-and-offers"
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.room\.label



The name the room screen gives that app\.



*Type:*
string



*Example:*

```nix
"Requests & Offers"
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.room\.part



The role of the app whose writes the room follows\.



*Type:*
string



*Example:*

```nix
"requests_and_offers"
```

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

```nix
"15s"
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.scrapeTargets



The node_exporter of every node Prometheus scrapes, and the name each
node goes by on the dashboards\. Prometheus attaches the name to every
series from the target as the ` node ` label, so a node that is down is
still shown by its name\.

As an attribute set, each key is the node’s name, and the value gives
its ` address ` (host:port) and, optionally, its ` site `, which becomes a
` site ` label\. As a list of host:port strings, each node is named after
the host part of its address, except that a loopback address
(127\.0\.0\.1, localhost, ::1) takes this machine’s
` networking.hostName `\. A list entry given by an IP address therefore
goes by that address on every dashboard, and evaluation warns about
it: give such a node a name with the attribute set form\.

No two targets may go by the same name: the dashboards aggregate by
` node `, so two targets named alike would read as one machine\. Two
list entries on one host (two ports of a loopback, say) need the
attribute set form\.



*Type:*
(list of string) or attribute set of (submodule)



*Default:*

```nix
[ ]
```



*Example:*

```nix
{
  lab-1 = { address = "edgenode-01:9100"; site = "Sensorica lab"; };
  lab-2 = { address = "edgenode-02:9100"; site = "Sensorica lab"; };
  homelab.address = "100.64.0.7:9100";
}

```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.secretKeyFile



Path on the target machine to a file holding Grafana’s
` security.secret_key `, the key it encrypts data source secrets with\.
Since NixOS 26\.05 Grafana has no default key and refuses to evaluate
without one\.

When null, the module generates a random key once, at first boot, in
` ${services.grafana.dataDir}/secret_key ` (mode 0400, owned by
` grafana `) and keeps it across rebuilds, so the key never enters the
Nix store\. Set this only to share one key between machines or to
restore one from a backup; like ` adminPasswordFile `, it is handed over
by systemd and can stay root-owned\.



*Type:*
null or absolute path not in the Nix store



*Default:*

```nix
null
```



*Example:*

```nix
"/var/lib/secrets/grafana-secret-key"
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.states\.historyWindow



How far back, as a Prometheus duration, a DHT with no peer is
remembered to have had one\. Within it the DHT reads “Lost contact”;
a DHT that had nobody in all of it, on a DNA no other node of the
fleet runs, reads “No one else yet”, which is normal for a node that
is alone\.



*Type:*
string matching the pattern \[0-9]+(ms|s|m|h|d|w|y)



*Default:*

```nix
"24h"
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.states\.inStepShare



The share of its best peer’s data a connected DHT must hold, on
average over ` shareWindow `, to read “In step” rather than “Catching
up”\. A healthy DHT rarely holds everything its best peer does, since
new data is always on its way, so 1 would read a working network as
behind for good; 0\.95 is what the Sensorica Moss node’s DHTs held on
2026-09-27\.



*Type:*
integer or floating point number between 0 and 1 (both inclusive)



*Default:*

```nix
0.95
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.states\.shareWindow



The window, as a Prometheus duration, the held share is averaged
over, so a DHT does not flap between “In step” and “Catching up” at
every write\.



*Type:*
string matching the pattern \[0-9]+(ms|s|m|h|d|w|y)



*Default:*

```nix
"10m"
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.states\.silentAfterSeconds



How long a DHT that knows peers may go without gossiping with any of
them before it reads “Lost contact”\.



*Type:*
positive integer, meaning >0



*Default:*

```nix
600
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-grafana\.states\.staleAfterSeconds



How old a conductor’s readings may get before every DHT of it reads
“No fresh readings” and its conductor state reads stale\. The default
covers the metrics timer’s 30 s interval plus the 15 s scrape, with
margin; raise it with ` conductorMetrics.interval `\.



*Type:*
positive integer, meaning >0



*Default:*

```nix
90
```

*Declared by:*
 - [modules/holochain-grafana\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-grafana.nix)



## services\.holochain-http-gateway\.enable



Whether to enable the Holochain HTTP gateway in front of the local conductor\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

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

```nix
"127.0.0.1"
```

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.adminPort



Admin websocket port of the conductor the gateway drives\. It becomes
` HC_GW_ADMIN_WS_URL=ws://127.0.0.1:<adminPort> `, which the binary
requires: without it the process exits immediately\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
config.services.holochain-edgenode.adminPort
```

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

```nix
[ ]
```



*Example:*

```nix
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

```nix
{ }
```



*Example:*

```nix
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

```nix
50
```

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

```nix
false
```

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

```nix
10240
```

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.port



Port the gateway listens on, passed as ` --port ` (` HC_GW_PORT `)\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
8090
```

*Declared by:*
 - [modules/holochain-http-gateway\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-http-gateway.nix)



## services\.holochain-http-gateway\.zomeCallTimeoutMs



Deadline for a single zome call, in milliseconds, as
` HC_GW_ZOME_CALL_TIMEOUT_MS `\. A call that outruns it answers 500\.



*Type:*
unsigned integer, meaning >=0



*Default:*

```nix
10000
```

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

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/holochain-windtunnel\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-windtunnel.nix)



## services\.holochain-windtunnel\.autoStart



Start the container at boot\. Set to false to keep the unit generated
but idle, which is what the VM test does: the test sandbox has no
network, so the image cannot be pulled there\.



*Type:*
boolean



*Default:*

```nix
true
```

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

```nix
"podman"
```

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

```nix
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

```nix
"nomad-client-${config.networking.hostName}"
```

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

```nix
"ghcr.io/holochain/wind-tunnel-runner@sha256:650c91806275681bc1961e0e55e85fa7fbf31bebe0c8665fc0a6af71ac330fa2"
```

*Declared by:*
 - [modules/holochain-windtunnel\.nix](https://github.com/Sensorica/nixos-holochain/blob/main/modules/holochain-windtunnel.nix)


