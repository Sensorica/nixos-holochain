# The admin plane's options, evaluated without booting anything: that
# `grafana.cookieSecure` reaches Grafana's `security.cookie_secure` both ways,
# and that `duckdns` hands ddclient the protocol, the name and the token file.
# vmTestAdminPlane covers what runs; this covers what each option renders.
{
  pkgs,
  nixos-holochain,
}: let
  inherit (pkgs) lib;

  evalWith = adminPlane:
    (pkgs.nixos {
      imports = [
        nixos-holochain.nixosModules.admin-plane
        nixos-holochain.nixosModules.holochain-grafana
      ];
      services.holochain-grafana.enable = true;
      # recursiveUpdate, not `//`: a shallow merge of `grafana.cookieSecure`
      # would drop `grafana.domain`, and with it the setting under test.
      services.admin-plane =
        lib.recursiveUpdate {
          enable = true;
          headscale = {
            domain = "hs.example.org";
            baseDomain = "fleet.internal";
          };
          grafana.domain = "grafana.example.org";
        }
        adminPlane;
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
    }).config;

  # The defaults, with Duck DNS on and a token file that is not the default.
  secure = evalWith {
    duckdns = {
      enable = true;
      name = "my-site";
      tokenFile = "/run/secrets/duckdns";
    };
  };
  # A host that takes logins over http://<address>:3000 as well.
  insecure = evalWith {grafana.cookieSecure = false;};

  ddclient = secure.services.ddclient;
in
  assert lib.assertMsg (secure.services.grafana.settings.security.cookie_secure == true)
  "cookieSecure left at its default must render cookie_secure = true";
  assert lib.assertMsg (insecure.services.grafana.settings.security.cookie_secure == false)
  "cookieSecure = false must render cookie_secure = false";
  assert lib.assertMsg ddclient.enable "duckdns.enable must enable ddclient";
  assert lib.assertMsg (ddclient.protocol == "duckdns") "ddclient must use the duckdns protocol, got ${ddclient.protocol}";
  assert lib.assertMsg (ddclient.domains == ["my-site"]) "ddclient domains must be [duckdns.name]";
  assert lib.assertMsg (ddclient.passwordFile == "/run/secrets/duckdns") "ddclient passwordFile must be duckdns.tokenFile";
  assert lib.assertMsg (!insecure.services.ddclient.enable) "ddclient must stay off without duckdns.enable";
    pkgs.runCommand "admin-plane-options" {} "touch $out"
