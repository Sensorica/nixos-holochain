# The hApps the Sensorica fleet runs in September (ADR-015).
#
# Nothing binary enters git (ADR-012): every bundle is fetched by hash at build
# time. Each `sha256` is `nix-prefetch-url` cross-checked against `sha256sum` of
# the resulting store path, and each URL was confirmed to answer 200 on
# 2026-08-28.
#
# All three are 0.6-line bundles, which is why the fleet pins Holochain 0.6.3:
# neither hREA, Kando nor Requests & Offers has published a 0.7 release.
{
  pkgs,
  hc,
}: rec {
  # hREA happ-0.4.0-beta, the ValueFlows/REA economic backend the Sensorica
  # network's own accounting is built on. 1 678 587 bytes.
  hrea = pkgs.fetchurl {
    url = "https://github.com/h-REA/hREA/releases/download/happ-0.4.0-beta/hrea.happ";
    sha256 = "7903de1fbe475b0076dcfc988c7afa1beb8b5a16aa38c6ad125522124c3321dc";
  };

  # Kando v0.17.5, the Foundation's kanban demo: the fastest way for a room of
  # participants to see their own writes reach every other node.
  kando = pkgs.fetchurl {
    url = "https://github.com/holochain-apps/kando/releases/download/v0.17.5/kando.happ";
    sha256 = "a4cdee64fe32720077e0aade94630f24d0da5e91da33ccbe5bfd894d9d359f28";
  };

  # Requests & Offers v0.5.2 publishes a `.webhapp` and nothing else, and a
  # conductor installs a `.happ`. So the bundle is unpacked at build time by the
  # `hc` of the same line: `hc web-app unpack` writes the inner
  # `requests_and_offers.happ` next to a `dist.zip` (the web UI, which a
  # conductor never looks at) and a `web-happ.yaml` manifest.
  requests-and-offers-webhapp = pkgs.fetchurl {
    url = "https://github.com/happenings-community/requests-and-offers/releases/download/v0.5.2/requests_and_offers.webhapp";
    sha256 = "e71c7e7869ee765d5931128679fef96ebf0fc035cd3b66bc16cc3514120d1eb6";
  };

  # sha256 of the unpacked bundle, for anyone reproducing this by hand:
  #   9d574a48458c339548476732be3656af6a3469167797d0bce0d25582d73dafe3
  # It is not pinned here because it is derived, not fetched: the `.webhapp`
  # above is the hash that has to match.
  requests-and-offers =
    pkgs.runCommand "requests-and-offers-0.5.2.happ" {
      nativeBuildInputs = [hc];
    } ''
      # `hc` writes into $HOME even for a pure unpack.
      export HOME="$TMPDIR"
      cp ${requests-and-offers-webhapp} bundle.webhapp
      hc web-app unpack bundle.webhapp -o unpacked
      cp unpacked/requests_and_offers.happ "$out"
    '';
}
