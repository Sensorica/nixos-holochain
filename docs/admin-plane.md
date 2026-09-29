# Admin plane: Headscale and a public Grafana

`nixosModules.admin-plane` turns one machine of a fleet into its admin plane: [Headscale](https://headscale.net), the self-hosted Tailscale coordination server the other machines log into, and optionally Grafana under its own public name. Both sit behind nginx with Let's Encrypt. Holochain does not use any of it; its peers meet through their own bootstrap and relay servers.

The client side is `examples/sensorica-fleet/hosts/remote-access.nix` (`sensorica.remoteAccess`): a Tailscale client logged into the fleet's Headscale, with the tailnet interface trusted so SSH and Grafana answer there without being opened to the LAN.

In the Sensorica fleet, `sensorica-holoport-01` runs it at `https://hs.sensorica.co` and `https://grafana.sensorica.co`, with MagicDNS names `<hostname>.sensorica.internal`. Tracked in [#70](https://github.com/Sensorica/nixos-holochain/issues/70).

## What the site needs, once

1. **DNS.** An A record for the Headscale name pointing at the site's public IPv4, and the Grafana name as a CNAME to it. At Sensorica both live at GoDaddy, whose DNS API is closed to accounts under ten domains, so they are plain records edited by hand.
2. **Router.** A DHCP reservation for the admin-plane machine, and TCP 80 and 443 forwarded to it. Nothing else: SSH (22), Grafana (3000) and Prometheus (9090) stay closed on the public address. Port 80 only serves the ACME challenge and the redirect to HTTPS.
3. **Grafana password.** With `grafana.domain` set, Grafana's login page is the only gate on a public name. `services.holochain-grafana.adminPasswordFile` must hold a strong password before the switch.

Order matters: the certificates are ordered during the switch, over port 80. A switch made before the DNS records resolve and the forwards exist leaves nginx on a self-signed placeholder; fix the cause, then `sudo systemctl restart acme-order-renew-<name>`.

## Deploy

On the machine, from its checkout of the fleet:

```sh
rebuild
systemctl is-active headscale nginx
```

From outside the site (a phone on mobile data, or any remote shell):

```sh
curl -s -o /dev/null -w "%{http_code}\n" https://hs.sensorica.co/health
curl -s -o /dev/null -w "%{http_code}\n" https://hs.sensorica.co/
curl -s -o /dev/null -w "%{http_code}\n" https://grafana.sensorica.co/login
```

`/health` answers 200, the bare name 403 with a "Private server" page, and Grafana's login 200.

## Join a machine

Create the user once, then a short-lived key per machine. `--user` takes the numeric id from `users list`, not the name.

```sh
sudo headscale users create sensorica
sudo headscale users list
sudo headscale preauthkeys create --user 1 --expiration 1h
```

On a fleet host, write the key root-only to `/var/lib/secrets/headscale-authkey`, set `sensorica.remoteAccess.enable = true` in its configuration, and `rebuild`. The key is read once, at the first connection.

On a laptop:

```sh
sudo tailscale up --login-server https://hs.sensorica.co --authkey KEY
```

The admin-plane machine pins its own Headscale name to `127.0.0.1`, so its own join never depends on the router looping the public address back. A laptop inside the site does depend on that; if `https://hs.sensorica.co/health` fails from the LAN but works from outside, join the laptop over a phone hotspot. The IP address is no substitute, because the certificate names only the domain.

## Use it

```sh
sudo headscale nodes list
ssh sensorica@sensorica-holoport-01.sensorica.internal
```

Grafana over the tailnet: `http://sensorica-holoport-01.sensorica.internal:3000`. Over the public name: `https://grafana.sensorica.co`.

## Revoke a machine

```sh
sudo headscale nodes list
sudo headscale nodes delete --identifier ID
```

## When the site's IP changes

With `dnsDrift.enable` (the default), a timer compares the site's public IPv4 with what each public name resolves to at a public resolver, every 15 minutes, and publishes `admin_plane_dns_matches_public_ip{name="..."}` through node_exporter's textfile collector: 1 when they agree, 0 when they do not. The journal of `admin-plane-dns-drift.service` names the old and new address.

When it reads 0: update the A record at the registrar to the new address (the CNAME follows), then wait for the TTL. Clients that are already joined keep working through the change as long as the coordination server is reachable again; nothing on them needs to change, because they know the server by name.

## Moving the admin plane to another site

The Headscale name is baked into every client's state, which is why it is a name and not an address. To move the server:

1. Stop Headscale on the old machine and copy its state directory (`/var/lib/headscale`: the SQLite database and the Noise private key) to the new one.
2. Enable `services.admin-plane` on the new machine with the same `headscale.domain`, and disable it on the old one.
3. Point the DNS records at the new site, set up its router forwards, and switch the new machine.

Clients reconnect to the same name with the same keys. Copying the state is what keeps the machine keys valid; starting from an empty database means re-joining every machine.
