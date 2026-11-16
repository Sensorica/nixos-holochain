# Called from nix/checks.nix with the per-system arguments of
# nix/shared.nix.
# The repository's layout, evaluated: every path an exported nixosModule
# lists in its imports lives under modules/holochain, modules/moss or
# modules/fleet, and no such path names the lab. The check reads those
# import lists; it does not open a path module to follow the imports
# written inside that file. The fleet's own modules
# leave with the fleet export (AD3); until then they are the exceptions
# below, and an exception that no longer matches fails too, so the list can
# only shrink.
{
  pkgs,
  self,
  ...
}: let
  inherit (pkgs) lib;

  exceptions = [
    # Moves with the fleet export (pm#20, AD2, AD3).
    "modules/sensorica-event-node.nix"
  ];

  root = toString self + "/";
  rel = p: lib.removePrefix root (toString p);

  # flake-parts wraps each module; walk the imports down to the paths that
  # belong to this flake. Functions and attribute sets without imports are
  # inline modules and carry no path.
  pathsOf = m:
    if builtins.isPath m || (builtins.isString m && lib.hasPrefix root m)
    then [(rel m)]
    else if builtins.isAttrs m && m ? imports
    then lib.concatMap pathsOf m.imports
    else [];

  layered = p: builtins.match "modules/(holochain|moss|fleet)(/.*)?" p != null;
  namesLab = p: builtins.match ".*[Ss][Ee][Nn][Ss][Oo][Rr][Ii][Cc][Aa].*" p != null;

  byModule = lib.mapAttrs (_: pathsOf) self.nixosModules;
  allPaths = lib.unique (lib.concatLists (lib.attrValues byModule));
  bad = builtins.filter (p: (!layered p || namesLab p) && !(builtins.elem p exceptions)) allPaths;
  stale = builtins.filter (e: !(builtins.elem e allPaths)) exceptions;
  report = lib.concatStringsSep "\n" (lib.mapAttrsToList (n: ps: "${n}: ${lib.concatStringsSep " " ps}") byModule);
in
  assert lib.assertMsg (allPaths != []) "layout: no module path found under ${root}";
  assert lib.assertMsg (bad == []) "layout: exported module paths outside modules/{holochain,moss,fleet} or naming the lab: ${toString bad}";
  assert lib.assertMsg (stale == []) "layout: exceptions that no longer match an exported module path (remove them): ${toString stale}";
    pkgs.writeText "layout" report
