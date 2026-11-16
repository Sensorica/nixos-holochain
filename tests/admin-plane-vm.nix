# Called from nix/checks.nix with the per-system arguments of
# nix/shared.nix.
# The admin plane end to end: a client joins the tailnet through
# nginx (the ts2021 upgrade is the part a proxy breaks), the bare
# name answers 403 with the private page, and Grafana answers on its
# own name. Let's Encrypt cannot run in the sandbox, so the test
# swaps ACME for a self-signed certificate the client trusts; the
# drift check needs the internet, so only its units are asserted.
{
  pkgs,
  self,
  ...
}: let
  hsName = "hs.admin-plane.test";
  grafanaName = "grafana.admin-plane.test";
  cert =
    pkgs.runCommand "admin-plane-test-cert" {
      nativeBuildInputs = [pkgs.openssl];
    } ''
      mkdir -p $out
      openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout $out/key.pem -out $out/cert.pem \
        -subj "/CN=${hsName}" \
        -addext "subjectAltName=DNS:${hsName},DNS:${grafanaName}"
    '';
  noAcme = name: {
    enableACME = pkgs.lib.mkForce false;
    sslCertificate = "${cert}/cert.pem";
    sslCertificateKey = "${cert}/key.pem";
  };
in
  pkgs.testers.nixosTest {
    name = "admin-plane";
    nodes.server = {nodes, ...}: {
      imports = [
        self.nixosModules.admin-plane
        self.nixosModules.holochain-grafana
      ];
      services.holochain-grafana.enable = true;
      services.admin-plane = {
        enable = true;
        headscale = {
          domain = hsName;
          baseDomain = "fleet.internal";
        };
        grafana.domain = grafanaName;
      };
      # Headscale fetches Tailscale's DERP map at startup and exits
      # when it cannot; the sandbox has no internet, so the test
      # serves its own relay instead, as nixpkgs' headscale test does.
      services.headscale.settings.derp = {
        server = {
          enabled = true;
          region_id = 999;
          stun_listen_addr = "0.0.0.0:3478";
        };
        urls = pkgs.lib.mkForce [];
      };
      networking.firewall.allowedUDPPorts = [3478];
      services.nginx.virtualHosts.${hsName} = noAcme hsName;
      services.nginx.virtualHosts.${grafanaName} = noAcme grafanaName;
      security.pki.certificateFiles = ["${cert}/cert.pem"];
      environment.systemPackages = [pkgs.curl];
      # The service list and health readings go where a fleet
      # host's node_exporter would read them.
      services.holochain-services.textfileDirectory = "/var/lib/node-text";
      systemd.tmpfiles.rules = ["d /var/lib/node-text 0755 root root - -"];
    };
    nodes.client = {nodes, ...}: {
      services.tailscale.enable = true;
      security.pki.certificateFiles = ["${cert}/cert.pem"];
      networking.hosts.${nodes.server.networking.primaryIPAddress} = [hsName grafanaName];
      environment.systemPackages = [pkgs.curl];
    };
    testScript = ''
      start_all()
      server.wait_for_unit("headscale.service")
      server.wait_for_unit("nginx.service")
      server.wait_for_unit("grafana.service")
      server.wait_for_open_port(443)

      with subtest("Headscale answers through nginx, the bare name is private"):
          client.wait_until_succeeds("curl -fsS https://${hsName}/health")
          code = client.succeed("curl -s -o /dev/null -w '%{http_code}' https://${hsName}/")
          assert code == "403", f"expected 403 on /, got {code}"
          body = client.succeed("curl -s https://${hsName}/")
          assert "Private server" in body, body

      with subtest("Plain HTTP only redirects"):
          code = client.succeed("curl -s -o /dev/null -w '%{http_code}' http://${hsName}/health")
          assert code == "301", f"expected 301 on port 80, got {code}"

      with subtest("Grafana answers on its public name with its public root URL"):
          client.wait_until_succeeds("curl -fsS https://${grafanaName}/api/health")
          login = client.succeed("curl -s https://${grafanaName}/login")
          assert "https://${grafanaName}/" in login, "root_url not rewritten"

      with subtest("A client joins the tailnet through the proxy"):
          server.succeed("headscale users create fleet")
          uid = server.succeed("headscale users list -o json | ${pkgs.jq}/bin/jq -r '.[0].id'").strip()
          key = server.succeed(f"headscale preauthkeys create --user {uid} --expiration 1h").strip().splitlines()[-1]
          client.wait_for_unit("tailscaled.service")
          client.succeed(f"tailscale up --login-server https://${hsName} --authkey {key} --hostname client")
          server.wait_until_succeeds("headscale nodes list -o json | ${pkgs.jq}/bin/jq -e 'map(select(.name == \"client\")) | length == 1'")
          client.wait_until_succeeds("tailscale ip -4 | grep -E '^100\\.'")

      with subtest("The dashboards list the admin plane, healthy through the certificate"):
          server.succeed("systemctl start holochain-service-health.service")
          health = server.succeed("cat /var/lib/node-text/holochain-service-health.prom")
          for unit in ["headscale.service", "nginx.service"]:
              assert f'holochain_service_healthy{{name="{unit}"}} 1' in health, health
          listed = server.succeed("cat /var/lib/node-text/holochain-services.prom")
          assert 'service="Remote access (Headscale)"' in listed, listed

      with subtest("The drift check is installed"):
          server.succeed("systemctl cat admin-plane-dns-drift.timer")
          server.succeed("systemctl cat admin-plane-dns-drift.service")
    '';
  }
