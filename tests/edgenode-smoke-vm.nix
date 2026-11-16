# A test function, bound in nix/shared.nix and applied in nix/checks.nix
# (and nix/falsifiers.nix) once per variant.
{
  adminCall,
  edgenodeNode,
  hcOnPath,
  pkgs,
  roomToWork,
  ...
}: {
  name,
  line,
  nodeExtra ? {},
}:
pkgs.testers.nixosTest {
  inherit name;
  nodes.machine = {
    imports = [edgenodeNode hcOnPath roomToWork nodeExtra];
    services.holochain-edgenode.enable = true;
  };
  testScript = ''
    import re

    machine.wait_for_unit("holochain-conductor.service")
    machine.wait_for_open_port(4444)

    state = machine.succeed("systemctl is-active holochain-conductor.service").strip()
    assert state == "active", f"expected active, got {state}"

    # The admin interface answering list-apps is what "the port is open"
    # is supposed to mean; a listening socket alone would not prove it.
    apps = machine.succeed("${adminCall.${line}} list-apps").strip()
    assert apps == "[]", f"expected no apps on a bare node, got {apps}"

    journal = machine.succeed("journalctl -u holochain-conductor --no-pager")
    offenders = [
        line
        for line in journal.splitlines()
        if re.search(r"(?i)error|panic|failed to parse", line)
    ]
    assert not offenders, "conductor journal is not clean:\n" + "\n".join(offenders)
  '';
}
