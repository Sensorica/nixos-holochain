# The Moss pilot's always-online node and bootstrap server

The Moss pilot (Nondominium's v0.1.0 peer-mesh release) runs Moss in `weave` dev mode on Holochain 0.7.1. Two things keep it from depending on its members' laptops, and both run on our Holoports through this repository: an always-online wdocker node that holds the group and the Nondominium tool's DHTs while the members are offline (nondominium [#166](https://github.com/Sensorica/nondominium/issues/166)), and the `kitsune2-bootstrap-srv` the members pass to `weave` as `--bootstrap-url` and `--relay-url` (nondominium [#122](https://github.com/Sensorica/nondominium/issues/122)). This page is the setup. [Moss always-online node](moss-node.md) describes the module underneath it for the 0.15 line.

Nothing on this page has been deployed. A change to a Holoport is Soushi's, from the steps at the end.

## What runs, and at which build

| Part | Package | Pin |
|---|---|---|
| wdocker | `packages.x86_64-linux.wdocker-0_16` | `@theweave/wdocker@next`, 0.16.0-rc.4, built from the Moss commit `6ba03097` it was published from (the commit of the Moss release `v0.16.0-rc.4-test.27`) |
| Its Holochain | inside `wdocker-0_16` | `holochain-0.7.1-mdns.8`, the Lightning Rod Labs fork release, sha256 `a9aa2642...3d098` |
| Bootstrap and relay | `packages.x86_64-linux.bootstrap-srv-0_7_1` | the `kitsune2-bootstrap-srv` asset of the stock `holochain-0.7.1` release, sha256 `f080b3ee...3a9d5` |

The Holochain is not stock. The Moss 0.16 release candidates ship a patched 0.7.1 (kitsune2 hello/PoK access control and mDNS LAN discovery) that advertises `HCP2P_PROTO_VER=1002` and rejects stock peers at preflight, so the field-test cohort is partitioned from every other Moss. A wdocker node on stock 0.7.1 would run beside the pilot and never see it. `holochain-checksums.json` at the pinned Moss commit names the fork release; `@theweave/cli@next` and `@theweave/wdocker@next` both carry the same block, which is how we know the pilot's `weave` runs it. The bootstrap server is not patched: Moss itself takes it from the stock release, and the server takes no part in the preflight between conductors.

The wdocker package carries two patches, both on top of the 0.15 package's one: `WDOCKER_HOLOCHAIN_BINARY` names the Holochain binary (so nothing is downloaded at runtime), and `WDOCKER_BOOTSTRAP_URL` and `WDOCKER_RELAY_URL` name the servers. wdocker 0.16 hard-codes Moss's production bootstrap and relay, and a node there would never meet members on ours. With the variables unset, the defaults are unchanged.

Moss's own warning applies: this build cannot talk to stock Moss, and a profile opened by 0.7.1 cannot be reopened by a 0.7.0 build. Bump the pins together when the pilot's build moves.

## The bootstrap and relay server

`services.holochain-bootstrap` gains an `nginx` block. With it, nginx holds ports 80 and 443 and the Let's Encrypt certificate, and the server listens on `127.0.0.1:7843` in plain HTTP behind it. nginx forwards `/relay` as a WebSocket, which is how the iroh relay talks.

```nix
{
  imports = [nixos-holochain.nixosModules.holochain-bootstrap];

  security.acme = {
    acceptTerms = true;
    defaults.email = "ops@example.org";
  };

  services.holochain-bootstrap = {
    enable = true;
    package = nixos-holochain.packages.${pkgs.system}.bootstrap-srv-0_7_1;
    openFirewall = true; # 80, 443 and UDP 7842
    nginx = {
      enable = true;
      host = "bootstrap.example.org"; # a public DNS name that reaches this machine
    };
  };
}
```

Members then start Moss with `--bootstrap-url https://bootstrap.example.org --relay-url https://bootstrap.example.org/relay`. The relay is open: anyone who can reach the host can relay traffic through it, which is what a limited demo cohort needs and nothing more. The server keeps its state in memory only; a restart refills within minutes as conductors republish.

QUIC address discovery cannot sit behind a TCP proxy. It stays on UDP 7842 on the machine itself with the server's self-signed certificate, and what a conductor does when it cannot validate that certificate was not tried here.

## The always-online node

```nix
{
  imports = [nixos-holochain.nixosModules.holochain-moss-node];

  services.holochain-moss-node = {
    enable = true;
    package = nixos-holochain.packages.${pkgs.system}.wdocker-0_16;
    name = "pilot";
    passwordFile = "/var/lib/secrets/moss-node-password";
    inviteFile = "/var/lib/secrets/moss-node-invite";
    profileName = "holoport-01";
    nodeDescription = "Sensorica always-online node";
    bootstrapUrl = "https://bootstrap.example.org";
    relayUrl = "https://bootstrap.example.org/relay";
    metrics.enable = false;
  };
}
```

- `moss-node.service` runs `wdaemon pilot` under its own user, with the conductor password as a systemd credential, and comes back whichever way it ends.
- `moss-node-join.service` is a oneshot. Once the daemon answers it runs `wdocker join-group` with the invite from `inviteFile`, then restarts the daemon, because wdocker pings Moss only for the groups present when it starts. A node that already holds a group does nothing, so the invite is read on the one start that joins and on no other. A join that fails (no network, the conductor still starting) retries every 60 seconds.
- The invite is the group's network seed. Only its path reaches the Nix store; systemd hands the file over as a credential. wdocker prints the invite and, after a join, the installed app, so the unit sends its output to a private file and the journal gets one of four reasons (`invalid invite (wrong-format)`, `(version-mismatch)`, `(invalid-seed)`, `(invalid-progenitor)`) or `Failed to fetch resource`, and nothing that can echo the seed. `moss-node join "INVITE"` at a terminal shows the whole error.
- The tools the group's stewards tagged "always-online nodes should install this tool" are installed by the daemon every five minutes, as on the 0.15 line. Tag the Nondominium tool in the group's settings.
- `metrics.enable = false`: the readings exporter asks the conductor through the edgenode's `hc`, and no `hc` of the 0.7.1 line was checked against this node. A Holoport that also runs the 0.6.3 fleet conductor keeps its 0.15 Moss node's readings; the pilot node shows on no dashboard yet.
- One node per machine: the unit, the user and the state directory are `moss-node` everywhere. A Holoport that runs the Sensorica 0.15 node cannot also run the pilot node, so the pilot's goes on another Holoport.

Write the two secret files as root before the switch, with no trailing newline, and keep the invite out of shell history (a leading space with `HISTCONTROL=ignorespace`):

```bash
printf '%s' "$(systemd-ask-password 'Moss conductor password:')" | install -m 0400 /dev/stdin /var/lib/secrets/moss-node-password
```

```bash
printf '%s' "$(systemd-ask-password 'Moss group invite:')" | install -m 0400 /dev/stdin /var/lib/secrets/moss-node-invite
```

The repository has no secret manager of its own: a secret is a root-only path, written on the machine (ADR-012). A deployment that keeps secrets in agenix points these two options at `config.age.secrets.<name>.path`; the module only needs a path.

## What the checks prove

`checks.x86_64-linux.vmTestPilotNode` boots three machines with no way out. `hub` runs the bootstrap server behind nginx on a throwaway certificate. `pilot` runs the 0.16 node pointed at the hub with a made-up unstewarded group's invite, and `badinvite` is the same node with an invite from the 0.15 line. It proves, and fails when any of these is false:

- the bootstrap answers on the loopback and through nginx over TLS, redirects plain HTTP, is unreachable on its backend port from another machine, and answers a WebSocket upgrade on `/relay` through nginx as it does directly;
- `wdocker --version` is 0.16.0-rc.4 and the conductor process is the `holochain-0.7.1-mdns.8` binary from the package, with the hub's URLs in its conductor config;
- the invite file joins a group (the group's app is installed on the conductor) and restarts the daemon, a second run of the join does nothing, and a killed daemon returns by itself;
- the conductor goes for the hub's URL (its log shows the attempt on the bootstrap), but gets no answer, see below;
- the made-up network seed is in no journal and in no unit file;
- an invite from another line fails with `version-mismatch` and the daemon stays up.

`checks.x86_64-linux.pilotNodeAcmeWiring` evaluates a host with ACME enabled and asserts the module asks for the certificate for the host and proxies it to the server.

## What waits for the dogfood

A VM cannot join the real pilot group: that needs a real invite and members who answer, and it belongs to the dogfood ([#125](https://github.com/Sensorica/nondominium/issues/125)). Not shown by anything here:

- the node joining the real Sensorica pilot group, activating the Nondominium tool and holding an NDO that one member made and the other reads after the creator goes offline (the acceptance of #166);
- two members on different machines finding each other through the hub and gossiping (the acceptance of #122);
- the pilot node completing a request to the hub. The patched conductor validates the bootstrap's certificate against its built-in roots and ignores the system store, so the VM's private CA ends in `invalid peer certificate: UnknownIssuer` (found with kitsune2 debug logging; the conductor also refuses a self-signed CA used as the server certificate, `CaUsedAsEndEntity`). The node reaching a hub on a certificate from a public CA is the first thing to check on the Holoports, and nothing here shows it. The hub's own half is shown: nginx, the TLS answer and the relay upgrade, with `curl`;
- a real Let's Encrypt certificate: the VM uses its own, and the ACME path is only evaluated;
- QUIC address discovery against the self-signed certificate, noted above;
- the group hApp download from GitHub on a first join (the VM places the file where wdocker looks for it, at the sha256 of the pinned `moss.config.json`).

## To put it on a Holoport

None of this has been run on a machine. Soushi decides which Holoport runs which part, and the order:

1. Point a DNS name at the Holoport that runs the bootstrap server and open ports 80 and 443 to it.
2. Add the bootstrap block above to that host, `nixos-rebuild build` it, then `switch`.
3. Check from outside: `curl -fsS https://bootstrap.example.org/health`.
4. On the Holoport that runs the node, write the two secret files, add the node block, build, then switch.
5. `moss-node status` shows the group once the join unit has finished; `journalctl -u moss-node-join` says `joined the group`.
