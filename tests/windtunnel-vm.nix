# Moved verbatim from flake.nix (AD1); called from nix/checks.nix with the
# shared per-system arguments of nix/shared.nix.
# The test sandbox has no network, so this asserts what the module
# generates rather than a running container; the image is pulled and
# run for real on the Builder's machine (see the PR body).
{
  pkgs,
  self,
  ...
}:
pkgs.testers.nixosTest {
  name = "holochain-windtunnel-unit";
  nodes.machine = {
    imports = [self.nixosModules.holochain-windtunnel];
    services.holochain-windtunnel = {
      enable = true;
      # No registry is reachable from the sandbox, so the unit is
      # generated but never started.
      autoStart = false;
    };
    networking.hostName = "edgenode-42";
    virtualisation.diskSize = 4096;
  };
  testScript = ''
    import re

    machine.wait_for_unit("multi-user.target")

    # The backend has to be there for the unit to mean anything.
    machine.succeed("podman --version")
    machine.succeed("podman ps")

    unit = machine.succeed("systemctl cat podman-wind-tunnel-runner.service")
    machine.log("unit:\n" + unit)

    exec_start = re.search(r"ExecStart=(\S+)", unit)
    assert exec_start is not None, "no ExecStart in the unit:\n" + unit
    run = machine.succeed(f"cat {exec_start.group(1)}")
    machine.log("generated run script:\n" + run)

    for flag in ["--net=host", "--privileged", "--cgroupns=host"]:
        assert flag in run, f"{flag} missing from the generated run command:\n{run}"

    assert "--hostname=nomad-client-edgenode-42" in run, run
    assert (
        "ghcr.io/holochain/wind-tunnel-runner@sha256:"
        "650c91806275681bc1961e0e55e85fa7fbf31bebe0c8665fc0a6af71ac330fa2"
    ) in run, run

    # `--pull missing` is the pull command the unit runs: podman
    # fetches the digest on first start and never again.
    assert "--pull missing" in run, run

    # autoStart = false has to mean exactly that, or a fleet would
    # start donating compute the moment the module is imported.
    enabled = machine.succeed(
        "systemctl is-enabled podman-wind-tunnel-runner.service || true"
    ).strip()
    machine.log(f"is-enabled: {enabled}")
    assert enabled != "enabled", enabled
    assert "wind-tunnel-runner" not in machine.succeed("podman ps")
  '';
}
