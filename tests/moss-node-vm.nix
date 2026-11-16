# Called from nix/moss.nix, on x86_64-linux only.
# The Moss node as a service (nixosModules.holochain-moss-node):
# systemd starts the daemon with no terminal, the password comes
# from a credential, the node survives a restart, and its
# readings reach node_exporter as conductor="Moss". Then the
# same machine with the password file gone must not reach
# "Daemon ready.": a daemon that starts without its password
# proves nothing about the credential.
{
  inputs,
  lib,
  pkgs,
  self,
  system,
  ...
}: let
  node = password: {
    imports = [
      self.nixosModules.holochain-edgenode
      self.nixosModules.holochain-moss-node
    ];
    virtualisation = {
      cores = 4;
      memorySize = 4096;
      diskSize = 8192;
    };
    services.holochain-edgenode = {
      enable = true;
      package = inputs.holonix-0_6.packages.${system}.holochain;
      hcPackage = inputs.holonix-0_6.packages.${system}.hc;
      metricsExporter.enable = true;
    };
    services.holochain-moss-node = {
      enable = true;
      name = "vmtest";
      passwordFile = "/etc/moss-node-password";
    };
    # "yes": the password; "empty": an empty file; "no": none.
    environment.etc = lib.mkIf (password != "no") {
      "moss-node-password" = {
        text =
          if password == "yes"
          then "vmtest"
          else "";
        mode = "0400";
      };
    };
  };
in
  pkgs.testers.nixosTest {
    name = "moss-node-service";
    nodes = {
      machine = node "yes";
      nopassword = node "no";
      emptypassword = node "empty";
    };
    testScript = ''
      machine.wait_for_unit("moss-node.service")
      machine.wait_until_succeeds(
          "journalctl -u moss-node --no-pager | grep -q 'Daemon ready.'", timeout=300)
      user = machine.succeed("systemctl show moss-node -p User --value").strip()
      assert user == "moss-node", user
      machine.succeed("moss-node --help | grep -q 'join \"INVITE_LINK\"'")
      listing = machine.succeed("moss-node wdocker list")
      assert "vmtest" in listing and "running" in listing, listing

      machine.succeed("systemctl start moss-node-metrics.service")
      # 300 s like the daemon waits: on a loaded runner the first "up" reading comes late (#110).
      machine.wait_until_succeeds(
          "grep -q 'holochain_conductor_up{conductor=\"Moss\"} 1' /var/lib/prometheus-node-exporter-text-files/moss-node.prom",
          timeout=300)

      machine.succeed("systemctl restart moss-node")
      machine.wait_until_succeeds(
          "test $(journalctl -u moss-node --no-pager | grep -c 'Daemon ready.') -ge 2", timeout=300)

      nopassword.wait_for_unit("multi-user.target")
      nopassword.sleep(20)
      journal = nopassword.succeed("journalctl -u moss-node --no-pager")
      assert "Daemon ready." not in journal, "the daemon started without its password"

      # An empty file is refused before wdaemon sees it, so no
      # conductor is created with an empty password.
      emptypassword.wait_until_succeeds(
          "journalctl -u moss-node --no-pager | grep -q 'is empty; write the conductor password'", timeout=300)
      emptypassword.fail("ls /var/lib/moss-node/.local/share/wdocker/0.15.x/conductors/vmtest")
    '';
  }
