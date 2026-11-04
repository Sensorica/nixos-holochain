# kitsune2-bootstrap-srv from the stock holochain-0.7.1 release, the binary
# Moss pins in holochain-checksums.json (`kitsune2-bootstrap-srv` has no
# `binarySources` entry there, so even the patched Moss 0.16 builds take it from
# holochain/holochain). It serves the bootstrap (`/bootstrap/{space}`) and the
# iroh relay (`/relay`) on one port, as holonix's `bootstrap-srv` does, but it
# is the build the Moss pilot's members would otherwise run on their own
# machines, not whichever kitsune2 holonix's main-0.7 lock resolves to.
#
# The patched Holochain the pilot runs (holochain-0.7.1-mdns.8) is partitioned
# from stock peers at preflight, between conductors. The server does not take
# part in that handshake, which is why Moss leaves it unpatched.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:
stdenv.mkDerivation {
  pname = "kitsune2-bootstrap-srv";
  version = "0.7.1";

  src = fetchurl {
    url = "https://github.com/holochain/holochain/releases/download/holochain-0.7.1/kitsune2-bootstrap-srv-x86_64-unknown-linux-gnu";
    # Moss's holochain-checksums.json, `kitsune2-bootstrap-srv.x86_64-unknown-linux-gnu`.
    sha256 = "f080b3ee4f3d4e37a2d790eb3df9722b5b1a1924d9d6c730c05c64859273a9d5";
  };

  dontUnpack = true;

  nativeBuildInputs = [autoPatchelfHook];
  # libgcc_s.
  buildInputs = [stdenv.cc.cc.lib];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/kitsune2-bootstrap-srv
    runHook postInstall
  '';

  meta = {
    description = "Kitsune2 bootstrap and relay server, the stock Holochain 0.7.1 release build";
    homepage = "https://github.com/holochain/kitsune2";
    mainProgram = "kitsune2-bootstrap-srv";
    platforms = ["x86_64-linux"];
  };
}
