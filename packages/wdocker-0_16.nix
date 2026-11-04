# wdocker on the Moss 0.16 line, at the build the pilot's Moss runs: the Moss
# monorepo at the commit `@theweave/wdocker@next` (0.16.0-rc.4) was published
# from, with the Holochain that commit's Moss ships.
#
# That Holochain is NOT stock. holochain-checksums.json at this commit points
# `holochain` at the Lightning Rod Labs fork release `holochain-0.7.1-mdns.8`
# (Holochain 0.7.1 plus the kitsune2 hello/PoK access module and mDNS LAN
# discovery). The fork advertises HCP2P_PROTO_VER=1002 instead of the stock
# protocol version, so it rejects stock peers at preflight: a wdocker node on
# stock Holochain 0.7.1 would sit beside the pilot's Moss and never see it. The
# release is public, so it is fetched by hash like any other binary, pinned to
# the sha256 Moss itself pins and to the digest GitHub reports for the asset.
# Every `@theweave/cli` and `@theweave/wdocker` on the npm `next` tag carries
# the same block.
#
# Differences from packages/wdocker.nix (the 0.15 line, Holochain 0.6.1):
#
# - Where the Holochain binary comes from: the fork release, not
#   holochain/holochain. src/binarySource.ts names the cached file after the
#   release tag (`holochain-v0.7.1-mdns.8-moss-0.16-wdocker`), and `wdocker
#   stop` identifies the conductor by the first 14 characters of that name.
# - The Moss libraries are no longer `file:` dependencies: wdocker declares
#   `^0.7.0-rc.1` ranges that the workspaces' own versions satisfy, so yarn
#   links them and no manifest rewrite is needed. The root manifest is still
#   narrowed to the five workspaces wdocker needs, and the upstream yarn.lock is
#   consumed unmodified (Yarn 1 does not fail `--frozen-lockfile` on entries
#   that are no longer used).
# - A second patch. wdocker 0.16 hard-codes Moss's production bootstrap and
#   relay (src/const.ts, picked at src/daemon/start.ts), and a node there would
#   never meet two pilot members who pass `--bootstrap-url` and `--relay-url` to
#   our own server. WDOCKER_BOOTSTRAP_URL and WDOCKER_RELAY_URL override them,
#   and the unset default is unchanged.
#
# The environment variable WDOCKER_HOLOCHAIN_BINARY (the same one-line patch as
# the 0.15 package) points wdocker at the binary in the store, and the wrapper
# sets it, so the daemon never downloads one at runtime.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  fetchYarnDeps,
  yarnConfigHook,
  nodejs_22,
  yarn,
  jq,
  makeWrapper,
  autoPatchelfHook,
  curl,
}: let
  # `@theweave/wdocker@next`'s gitHead, which is also the commit of the Moss
  # release tag v0.16.0-rc.4-test.27.
  mossRev = "6ba03097f3a2c3a603775979fd22eb6ee8d5aa5d";
  mossVersion = "0.16.0-rc.4";

  # The fork release holochain-checksums.json names, and the sha256 of its
  # x86_64 Linux asset (checksums-sha256.txt of the release, the file's own
  # `holochain.x86_64-unknown-linux-gnu`, and GitHub's asset digest agree).
  holochainVersion = "0.7.1";
  forkTag = "holochain-0.7.1-mdns.8";
  holochainSha256 = "a9aa26428903c6f045a9364cf08ead42ee095be048c2b6340b282d1d2003d098";
  holochain = fetchurl {
    url = "https://github.com/lightningrodlabs/holochain/releases/download/${forkTag}/holochain-x86_64-unknown-linux-gnu";
    sha256 = holochainSha256;
  };

  # src/binarySource.ts: `holochain-v<tag minus "holochain-">-<binariesAppendix>-wdocker`.
  holochainBinaryName = "holochain-v${lib.removePrefix "holochain-" forkTag}-moss-0.16-wdocker";

  # The workspaces wdocker needs, in build order.
  workspaces = [
    "libs/api"
    "shared/types"
    "shared/utils"
    "shared/group-client"
    "wdocker"
  ];
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "wdocker";
    version = mossVersion;

    # The Holochain this wdocker runs, for the Moss node module's service list,
    # which shows it next to wdocker's own version.
    passthru = {
      holochainVersion = lib.removePrefix "holochain-" forkTag;
      inherit holochain;
      # What the Moss node module may ask of this package: the patch above, and
      # the environment variables of wdocker's README (§ Headless usage).
      overridesBootstrap = true;
      takesInviteFromEnvironment = true;
    };

    src = fetchFromGitHub {
      owner = "lightningrodlabs";
      repo = "moss";
      rev = mossRev;
      hash = "sha256-5ubm9XeFblIjCI0v+xgcSukPqYbqXWzCSdHA2Cpilzo=";
    };

    yarnOfflineCache = fetchYarnDeps {
      yarnLock = "${finalAttrs.src}/yarn.lock";
      hash = "sha256-0MuOp5oKB3hot2QrdUkwdx966PxIYGalGfDS3gRCZ70=";
    };

    nativeBuildInputs = [
      yarnConfigHook
      nodejs_22
      yarn
      jq
      makeWrapper
      autoPatchelfHook
    ];

    # libgcc_s for the Holochain binary and the napi addon.
    buildInputs = [stdenv.cc.cc.lib];

    postPatch = ''
      # Only the workspaces wdocker needs, and none of the Electron app's
      # dependencies, scripts or postinstall.
      jq --argjson ws '${builtins.toJSON workspaces}' \
        '{name, version, private, workspaces: $ws}' package.json > package.json.new
      mv package.json.new package.json

      # The workspaces' tests import vitest, which the narrowed manifest no
      # longer installs, and their tsconfigs compile them with the sources.
      find libs shared wdocker -name '*.test.ts' -not -path '*/node_modules/*' -delete

      # Let the environment name the Holochain binary (see the header).
      substituteInPlace wdocker/src/filesystem.ts \
        --replace-fail \
          'return path.join(this.binsDir, HOLOCHAIN_BINARY_NAME);' \
          'return process.env.WDOCKER_HOLOCHAIN_BINARY || path.join(this.binsDir, HOLOCHAIN_BINARY_NAME);'

      # Let the environment name the bootstrap and relay servers (see the header).
      substituteInPlace wdocker/src/daemon/start.ts \
        --replace-fail \
          'const bootstrapUrl = PRODUCTION_BOOTSTRAP_URLS[0];' \
          'const bootstrapUrl = process.env.WDOCKER_BOOTSTRAP_URL || PRODUCTION_BOOTSTRAP_URLS[0];' \
        --replace-fail \
          'const relayUrl = PRODUCTION_RELAY_URLS[0];' \
          'const relayUrl = process.env.WDOCKER_RELAY_URL || PRODUCTION_RELAY_URLS[0];'

      # The pins above must be the ones this commit ships.
      [ "$(jq -r .holochain moss.config.json)" = "${holochainVersion}" ]
      [ "$(jq -r .binariesAppendix moss.config.json)" = "moss-0.16" ]
      [ "$(jq -r .binarySources.holochain.binariesRepo holochain-checksums.json)" = "lightningrodlabs/holochain" ]
      [ "$(jq -r .binarySources.holochain.binariesTag holochain-checksums.json)" = "${forkTag}" ]
      [ "$(jq -r '.holochain["x86_64-unknown-linux-gnu"]' holochain-checksums.json)" = "${holochainSha256}" ]
      [ "$(jq -r .version wdocker/package.json)" = "${mossVersion}" ]
    '';

    buildPhase = ''
      runHook preBuild

      tsc=$PWD/node_modules/typescript/bin/tsc
      for ws in ${lib.concatStringsSep " " (lib.init workspaces)}; do
        echo "tsc: $ws"
        (cd "$ws" && node "$tsc")
      done

      # wdocker's own build script: tsc, then the files const.ts reads from
      # next to itself at runtime.
      (cd wdocker && yarn --offline run build)

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Drop the build-only dependencies (typescript and friends).
      yarn install \
        --offline --frozen-lockfile --production \
        --ignore-engines --ignore-scripts --no-progress --non-interactive

      dest=$out/lib/wdocker
      mkdir -p $dest
      cp -r package.json node_modules $dest/
      for ws in ${lib.concatStringsSep " " workspaces}; do
        mkdir -p "$dest/$ws"
        cp -r "$ws/package.json" "$ws/dist" "$dest/$ws/"
        if [ -d "$ws/node_modules" ]; then cp -r "$ws/node_modules" "$dest/$ws/"; fi
      done

      # node-gyp-build prebuilds for other targets: musl builds that no glibc
      # system loads and autoPatchelf cannot satisfy, and foreign platforms.
      find $dest -path '*/prebuilds/*' -name '*.musl.node' -delete
      find $dest -type d -path '*/prebuilds/*' ! -name 'linux-x64' -prune -exec rm -rf {} +

      install -Dm755 ${holochain} $out/libexec/wdocker/${holochainBinaryName}

      # `wdocker start` spawns `node daemon.js` by name and downloads the group
      # hApp with `curl` (src/utils.ts).
      for bin in wdocker:cli.js wdaemon:daemon/daemon.js; do
        makeWrapper ${lib.getExe nodejs_22} "$out/bin/''${bin%%:*}" \
          --add-flags "$dest/wdocker/dist/''${bin#*:}" \
          --prefix PATH : ${lib.makeBinPath [nodejs_22 curl]} \
          --set-default WDOCKER_HOLOCHAIN_BINARY $out/libexec/wdocker/${holochainBinaryName}
      done

      runHook postInstall
    '';

    meta = {
      description = "Moss 0.16 always-online node (wdocker) with the patched Holochain 0.7.1 the pilot's Moss runs";
      homepage = "https://github.com/lightningrodlabs/moss/tree/${mossRev}/wdocker";
      # Declared in wdocker/package.json; the repository has no LICENSE file at
      # its root.
      license = lib.licenses.cal10;
      mainProgram = "wdocker";
      platforms = ["x86_64-linux"];
    };
  })
