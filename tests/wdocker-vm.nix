# Called from nix/moss.nix, on x86_64-linux only.
# The packaged wdocker brings up a throwaway conductor on NixOS
# without nix-ld and without downloading a Holochain binary. The
# VM has no network, so a download attempt would fail the test.
# The daemon reads its password on stdin, the one entry point
# that needs no TTY; joining a group needs an invite and is #28's.
{
  pkgs,
  self,
  system,
  ...
}: let
  wdocker = self.packages.${system}.wdocker-0_15;
  root = "/root/.local/share/wdocker/0.15.x";
in
  pkgs.testers.nixosTest {
    name = "wdocker-smoke";
    nodes.machine = {
      # The conductor alone takes about 900 MB.
      virtualisation = {
        cores = 4;
        memorySize = 4096;
        diskSize = 8192;
      };
      environment.systemPackages = [wdocker];
    };
    testScript = ''
      import re

      machine.wait_for_unit("multi-user.target")
      machine.succeed(
          "systemd-run --unit=wdaemon-smoke --setenv=HOME=/root"
          " ${pkgs.runtimeShell} -c 'printf vmtest | ${wdocker}/bin/wdaemon smoke'"
      )
      machine.wait_until_succeeds(
          "journalctl -u wdaemon-smoke --no-pager | grep -q 'Daemon ready.'",
          timeout=300,
      )
      journal = machine.succeed("journalctl -u wdaemon-smoke --no-pager")
      assert "No holochain binary found" not in journal, journal

      # Nothing was fetched into wdocker's own bins directory.
      bins = machine.succeed("ls -A ${root}/bins").strip()
      assert bins == "", f"wdocker downloaded into bins: {bins}"

      # The conductor is the packaged binary, and it carries the
      # process name `wdocker stop` looks for. pgrep patterns stop
      # at the kernel's 15-character comm, hence no escaped dot.
      pid = machine.succeed("pgrep '^holochain-v0.6'").strip()
      exe = machine.succeed(f"readlink /proc/{pid}/exe").strip()
      assert exe == "${wdocker}/libexec/wdocker/holochain-v0.6.1-moss-0.15-wdocker", exe

      config = machine.succeed(
          "cat ${root}/conductors/smoke/conductor/conductor-config.yaml"
      )
      admin = re.search(r"port: (\d+)", config)
      assert admin, f"no admin port in conductor-config.yaml:\n{config}"
      machine.wait_for_open_port(int(admin.group(1)))

      listing = machine.succeed("HOME=/root wdocker list")
      machine.log(listing)
      assert re.search(r"smoke\s.*running", listing), listing

      machine.succeed("HOME=/root wdocker stop smoke")
      machine.wait_until_fails(f"kill -0 {pid}", timeout=60)
    '';
  }
