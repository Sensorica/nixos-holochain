# The always-online node for the Moss pilot (#166) and the bootstrap and relay
# server it and the pilot's members use (#122), in one network with no way out.
#
# `hub` runs kitsune2-bootstrap-srv (the stock Holochain 0.7.1 release build)
# behind nginx on a certificate. `pilot` runs the 0.16 wdocker with the patched
# Holochain 0.7.1 the pilot's Moss ships, pointed at the hub, with its group
# invite in a root-only file. `badinvite` is the same node with an invite from
# the other Moss line, which must fail without taking the daemon down or
# printing the invite.
#
# What a VM can show and what it cannot. It shows that the services start, that
# the daemon runs the fork binary at the hub's address, that the invite file
# joins a group once (an unstewarded group made up for the test, whose network
# seed is a string of the test's own) and not again, that nothing prints the
# seed, and that the node comes back after its processes are killed. It cannot
# show that the node joins the real pilot group: that needs a real invite and
# members to answer, and belongs to the dogfood (#125). The certificate is a
# throwaway the test generates; the ACME path is only evaluated (acmeWiring).
{
  pkgs,
  nixos-holochain,
  wdocker,
  bootstrapSrv,
}: let
  inherit (pkgs) lib;

  host = "bootstrap.test";

  # A throwaway CA and a server certificate it signs, keys and all, in the Nix
  # store: fine for a test, and the reason this never serves a real name. Two
  # certificates, because the conductor's TLS stack refuses a self-signed CA
  # used as the server's own certificate (CaUsedAsEndEntity, seen in the first
  # runs of this test). Only ca.pem is trusted; the CA key stays in the build.
  cert = pkgs.runCommand "pilot-node-test-cert" {nativeBuildInputs = [pkgs.openssl];} ''
    mkdir $out
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -subj "/CN=pilot test CA" -addext basicConstraints=critical,CA:TRUE \
      -keyout ca.key -out $out/ca.pem
    openssl req -newkey rsa:2048 -nodes -subj /CN=${host} \
      -keyout $out/key.pem -out leaf.csr
    printf 'subjectAltName=DNS:${host}\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' > ext
    openssl x509 -req -in leaf.csr -CA $out/ca.pem -CAkey ca.key -CAcreateserial \
      -days 3650 -extfile ext -out $out/cert.pem
  '';

  # The group hApp the packaged wdocker would download, at the version and sha256
  # of its own moss.config.json. The VM has no network, so it is put where
  # wdocker looks for it before it tries to download it.
  groupHappSha256 = "636a7b752256e6b6aa4cd058962b609cbda3843d047bdc6533bac045a5e24a2c";
  groupHapp = pkgs.fetchurl {
    url = "https://github.com/lightningrodlabs/moss/releases/download/group-happ-v0.16.0-rc.1/group.happ";
    sha256 = groupHappSha256;
  };
  wdockerRoot = "/var/lib/moss-node/.local/share/wdocker/0.16.0-rc";

  # An unstewarded group (`progenitor=null`) with a seed that exists only here.
  seed = "pilot-vm-test-seed-7f3a";
  invite = "weave-0.16://invite/${seed}&progenitor=null";
  # An invite from the Moss 0.15 line: wdocker 0.16 refuses it.
  oldInvite = "weave-0.15://invite/old-line-seed-91c2&progenitor=null";

  node = {
    inviteText,
    nodes,
  }: {
    imports = [nixos-holochain.nixosModules.holochain-moss-node];
    virtualisation = {
      cores = 4;
      memorySize = 4096;
      diskSize = 8192;
    };
    networking.extraHosts = "${nodes.hub.networking.primaryIPAddress} ${host}";
    # The conductor trusts the system's certificate store.
    security.pki.certificateFiles = ["${cert}/ca.pem"];
    services.holochain-moss-node = {
      enable = true;
      package = wdocker;
      name = "pilot";
      passwordFile = "/etc/moss-node-password";
      inviteFile = "/etc/moss-node-invite";
      profileName = "vm-pilot-node";
      nodeDescription = "VM test node";
      bootstrapUrl = "https://${host}";
      relayUrl = "https://${host}/relay";
      metrics.enable = false;
    };
    environment.etc = {
      "moss-node-password" = {
        text = "vmtest";
        mode = "0400";
      };
      "moss-node-invite" = {
        text = inviteText;
        mode = "0400";
      };
    };
    systemd.tmpfiles.rules = let
      own = "moss-node moss-node";
    in [
      "d /var/lib/moss-node 0700 ${own} -"
      "d /var/lib/moss-node/.local 0700 ${own} -"
      "d /var/lib/moss-node/.local/share 0700 ${own} -"
      "d /var/lib/moss-node/.local/share/wdocker 0700 ${own} -"
      "d ${wdockerRoot} 0700 ${own} -"
      "d ${wdockerRoot}/happs 0700 ${own} -"
      "C ${wdockerRoot}/happs/${groupHappSha256}.happ 0600 ${own} - ${groupHapp}"
      "d ${wdockerRoot}/conductors 0700 ${own} -"
      "d ${wdockerRoot}/conductors/pilot 0700 ${own} -"
      "f+ ${wdockerRoot}/conductors/pilot/._config.json 0600 ${own} - {\"checkForGroupsAndToolsFrequencySeconds\":300,\"defaultProfileName\":\"vm\",\"defaultNodeDescription\":\"vm\",\"rustLog\":\"warn,kitsune2=debug,kitsune2_core=debug,kitsune2_api=debug,holochain_p2p=debug,iroh=info\"}"
    ];
  };

  # wdocker as the node's user, with the password the VM's file holds.
  wdockerCmd = args: "runuser -u moss-node -- env HOME=/var/lib/moss-node WDOCKER_PASSWORD=vmtest ${wdocker}/bin/wdocker ${args}";

  # A WebSocket upgrade request, which is how the iroh relay is reached.
  upgrade = url: "curl -sS -o /dev/null -w '%{http_code}' --http1.1 --max-time 5 -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' --cacert ${cert}/ca.pem ${url} || true";
in {
  vm = pkgs.testers.nixosTest {
    name = "moss-pilot-node";
    nodes = {
      hub = {nodes, ...}: {
        imports = [nixos-holochain.nixosModules.holochain-bootstrap];
        networking.extraHosts = "127.0.0.1 ${host}";
        services.holochain-bootstrap = {
          enable = true;
          package = bootstrapSrv;
          openFirewall = true;
          nginx = {
            enable = true;
            inherit host;
          };
        };
        # The module asks for a Let's Encrypt certificate; the test has none to
        # ask for.
        services.nginx.virtualHosts.${host} = {
          enableACME = lib.mkForce false;
          sslCertificate = "${cert}/cert.pem";
          sslCertificateKey = "${cert}/key.pem";
        };
        environment.systemPackages = [pkgs.curl];
      };
      pilot = {nodes, ...}:
        node {
          inviteText = invite;
          inherit nodes;
        };
      badinvite = {nodes, ...}:
        node {
          inviteText = oldInvite;
          inherit nodes;
        };
    };

    testScript = ''
      start_all()

      # The bootstrap server, behind nginx on a certificate.
      hub.wait_for_unit("holochain-bootstrap.service")
      hub.wait_for_unit("nginx.service")
      hub.wait_until_succeeds("curl -fsS http://127.0.0.1:7843/health", timeout=60)
      hub.succeed("curl -fsS --cacert ${cert}/ca.pem https://${host}/health")
      hub.succeed("systemctl show holochain-bootstrap -p ExecStart --value | grep -q '127.0.0.1:7843'")
      # Plain HTTP goes to HTTPS, and the server is not reachable on its own
      # port from another machine.
      assert "301" in hub.succeed("curl -sS -o /dev/null -w '%{http_code}' http://${host}/health"), "forceSSL"
      pilot.fail("curl -sS --max-time 5 http://hub:7843/health")
      # The relay answers an upgrade through nginx as it does on the loopback.
      direct = hub.succeed("${upgrade "http://127.0.0.1:7843/relay"}").strip()
      proxied = hub.succeed("${upgrade "https://${host}/relay"}").strip()
      hub.log(f"relay upgrade: direct {direct}, through nginx {proxied}")
      assert direct == proxied, (direct, proxied)
      assert proxied not in ("404", "502", "000"), proxied

      # The packages are the pins.
      pilot.succeed("${wdocker}/bin/wdocker --version | grep -qx '0.16.0-rc.4'")
      pilot.succeed("${wdocker}/libexec/wdocker/holochain-v0.7.1-mdns.8-moss-0.16-wdocker --version | grep -qx 'holochain 0.7.1'")
      hub.succeed("${bootstrapSrv}/bin/kitsune2-bootstrap-srv --version | grep -qx 'kitsune2_bootstrap_srv 0.5.1'")

      # The node starts with no terminal and joins the group from the invite file.
      pilot.wait_for_unit("moss-node.service")
      pilot.wait_until_succeeds("journalctl -u moss-node --no-pager | grep -q 'Daemon ready.'", timeout=300)
      pilot.wait_until_succeeds("journalctl -u moss-node-join --no-pager | grep -q 'joined the group'", timeout=600)
      pilot.wait_until_succeeds("test $(journalctl -u moss-node --no-pager | grep -c 'Daemon ready.') -ge 2", timeout=300)
      assert pilot.succeed("systemctl show moss-node-join -p Result --value").strip() == "success"
      groups = pilot.succeed("${wdockerCmd "list-groups pilot"}")
      pilot.log(groups)
      assert "ENABLED" in groups, groups
      pilot.succeed("${wdockerCmd "list-apps pilot"} | grep -q \"installed_app_id: 'group#\"")

      # It runs the fork binary, on the hub's bootstrap and relay.
      pilot.succeed("pgrep -af holochain-v0.7.1-mdns.8-moss-0.16-wdocker")
      pid = pilot.succeed("pgrep -f '^${wdocker}/libexec/wdocker/holochain-v0.7.1-mdns.8' | head -1").strip()
      exe = pilot.succeed(f"readlink /proc/{pid}/exe").strip()
      assert exe == "${wdocker}/libexec/wdocker/holochain-v0.7.1-mdns.8-moss-0.16-wdocker", exe
      config = pilot.succeed("cat ${wdockerRoot}/conductors/pilot/conductor/conductor-config.yaml")
      assert "bootstrap_url: https://${host}" in config, config
      assert "relay_url: https://${host}/relay" in config, config
      # And it goes for the hub. It cannot get an answer: the conductor trusts
      # only its built-in roots, not the system store, so the test's private CA
      # ends in `UnknownIssuer`. A real certificate (ACME) is the dogfood's.
      pilot.wait_until_succeeds(
          "grep -q 'failure contacting bootstrap server' ${wdockerRoot}/conductors/pilot/logs/wdocker.log", timeout=300)

      # The invite's network seed is in no journal and not on the command line of
      # anything still running.
      for machine in (pilot, hub):
          machine.fail("journalctl --no-pager | grep -q ${seed}")
      pilot.fail("systemctl cat moss-node.service moss-node-join.service | grep -q ${seed}")

      # No readings unit when metrics are off.
      pilot.fail("systemctl cat moss-node-metrics.timer")

      # Restart-safe: killed, it comes back by itself and does not join twice.
      before = int(pilot.succeed("journalctl -u moss-node --no-pager | grep -c 'Daemon ready.'"))
      pilot.succeed("systemctl kill -s KILL moss-node.service")
      pilot.wait_until_succeeds(
          f"test $(journalctl -u moss-node --no-pager | grep -c 'Daemon ready.') -gt {before}", timeout=300)
      pilot.succeed("systemctl restart moss-node-join.service")
      pilot.succeed("journalctl -u moss-node-join --no-pager | grep -q 'a group is already joined'")
      after = int(pilot.succeed("journalctl -u moss-node --no-pager | grep -c 'Daemon ready.'"))
      pilot.sleep(30)
      assert int(pilot.succeed("journalctl -u moss-node --no-pager | grep -c 'Daemon ready.'")) == after

      # An invite from the other line is refused, with its reason and nothing
      # that echoes the invite; the daemon is not the worse for it.
      badinvite.wait_until_succeeds("journalctl -u moss-node-join --no-pager | grep -q 'version-mismatch'", timeout=600)
      badinvite.fail("journalctl --no-pager | grep -q old-line-seed")
      badinvite.succeed("systemctl is-active moss-node.service")
    '';
  };

  # The ACME path, evaluated: the module's vhost asks for a certificate and the
  # server then waits behind it. A VM cannot get one.
  acmeWiring = let
    system = pkgs.nixos {
      imports = [nixos-holochain.nixosModules.holochain-bootstrap];
      services.holochain-bootstrap = {
        enable = true;
        package = bootstrapSrv;
        nginx = {
          enable = true;
          host = "bootstrap.example.org";
        };
      };
      security.acme = {
        acceptTerms = true;
        defaults.email = "ops@example.org";
      };
      boot.loader.grub.enable = false;
      fileSystems."/" = {
        device = "/dev/null";
        fsType = "ext4";
      };
      system.stateVersion = "26.05";
    };
    cfg = system.config;
    vhost = cfg.services.nginx.virtualHosts."bootstrap.example.org";
  in
    assert cfg.security.acme.certs ? "bootstrap.example.org";
    assert vhost.forceSSL && vhost.enableACME;
    assert vhost.locations."/".proxyPass == "http://127.0.0.1:7843";
    assert vhost.locations."/".proxyWebsockets;
    assert lib.hasInfix "--listen 127.0.0.1:7843" cfg.systemd.services.holochain-bootstrap.serviceConfig.ExecStart;
      pkgs.runCommand "pilot-node-acme-wiring" {} "touch $out";
}
