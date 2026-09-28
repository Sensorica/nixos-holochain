# wdocker, the headless "always-online node" of Moss (the Weave), built from
# the tagged Moss monorepo at github.com/lightningrodlabs/moss.
#
# Why not the npm package: `@theweave/wdocker@0.15.4` on npm still carries
# `file:../shared/utils` style dependencies in its package.json, so
# `wdocker run` dies with ERR_MODULE_NOT_FOUND for @theweave/utils. The CLI
# only works when built inside the monorepo, next to the workspaces it
# depends on.
#
# How the `file:` dependencies are resolved: wdocker declares @theweave/api,
# @theweave/utils and @theweave/group-client as `file:../libs/api` and so on.
# Yarn 1 copies a `file:` dependency into node_modules at install time, which
# is before anything is built, so the copy has no `dist/` and the import
# fails. Here the three are rewritten to the workspaces' own version numbers,
# which yarn resolves as workspace links; building the workspaces in
# dependency order then fills the very directories node_modules points at.
# The root manifest is narrowed to the five workspaces wdocker needs, so the
# Electron app, its iframes and the test suite are neither installed nor
# shipped. Yarn 1 does not fail `--frozen-lockfile` on lockfile entries that
# are no longer used, so the upstream yarn.lock is consumed unmodified.
#
# The Holochain binary: wdocker keeps it at
# `<data>/wdocker/<0.15.x>/bins/holochain-v0.6.1-moss-0.15-wdocker` and
# downloads it from the Holochain GitHub release when that file does not
# exist (src/daemon/start.ts:137, the path from src/filesystem.ts:232 and
# src/const.ts:46). Existence is the only test: the sha256 is checked once,
# after a download (src/utils.ts:76-83), never on a file already present.
# This package fetches the same release asset, pinned to the sha256 Moss
# itself pins in holochain-checksums.json, patches its ELF interpreter so it
# runs on NixOS without nix-ld, and a one-line patch lets
# WDOCKER_HOLOCHAIN_BINARY override the path. The wrapper sets it, so the
# daemon never downloads a binary at runtime.
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
  mossVersion = "0.15.8";

  # Moss's own pins for this tag: moss.config.json gives the Holochain
  # version, holochain-checksums.json the sha256 of each release asset. The
  # build checks both against the source, so a bump that forgets one fails.
  holochainVersion = "0.6.1";
  holochainSha256 = "423f1111773c83c4c4f07e0bb338289d9bf0c5fa53dd31414b05b0dc8119ada7";
  holochain = fetchurl {
    url = "https://github.com/holochain/holochain/releases/download/holochain-${holochainVersion}/holochain-x86_64-unknown-linux-gnu";
    sha256 = holochainSha256;
  };

  # HOLOCHAIN_BINARY_NAME in src/const.ts:46. The file keeps this name
  # because `wdocker stop` identifies the conductor process by the first 14
  # characters of its process name (src/commands/stop.ts:26).
  holochainBinaryName = "holochain-v${holochainVersion}-moss-0.15-wdocker";

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

    # The Holochain this wdocker runs, for the Moss node module's service
    # list, which shows it next to wdocker's own version.
    passthru = {inherit holochainVersion;};

    src = fetchFromGitHub {
      owner = "lightningrodlabs";
      repo = "moss";
      tag = "v${mossVersion}";
      hash = "sha256-yB2XEBxsHR3ZULPEkWYuIByAOynHSp/0XF24HXVWa8I=";
    };

    yarnOfflineCache = fetchYarnDeps {
      yarnLock = "${finalAttrs.src}/yarn.lock";
      hash = "sha256-wSeKZDqBLwmy3rEmeG25HIklOXS/NquL2Fq2yX581eM=";
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

      # `file:` dependencies become workspace links (see the header).
      api=$(jq -r .version libs/api/package.json)
      utils=$(jq -r .version shared/utils/package.json)
      gc=$(jq -r .version shared/group-client/package.json)
      jq --arg api "$api" --arg utils "$utils" --arg gc "$gc" '
        .dependencies["@theweave/api"] = $api
        | .dependencies["@theweave/utils"] = $utils
        | .dependencies["@theweave/group-client"] = $gc
      ' wdocker/package.json > wdocker/package.json.new
      mv wdocker/package.json.new wdocker/package.json

      # Let the environment name the Holochain binary (see the header).
      substituteInPlace wdocker/src/filesystem.ts \
        --replace-fail \
          'return path.join(this.binsDir, HOLOCHAIN_BINARY_NAME);' \
          'return process.env.WDOCKER_HOLOCHAIN_BINARY || path.join(this.binsDir, HOLOCHAIN_BINARY_NAME);'

      # The pins above must be the ones this tag ships.
      [ "$(jq -r .holochain moss.config.json)" = "${holochainVersion}" ]
      [ "$(jq -r '.holochain["x86_64-unknown-linux-gnu"]' holochain-checksums.json)" = "${holochainSha256}" ]
    '';

    buildPhase = ''
      runHook preBuild

      tsc=$PWD/node_modules/typescript/bin/tsc
      for ws in ${lib.concatStringsSep " " (lib.init workspaces)}; do
        echo "tsc: $ws"
        (cd "$ws" && node "$tsc")
      done

      # wdocker's own build script: tsc, then the three files const.ts reads
      # from next to itself at runtime.
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

      # `wdocker start` spawns `node daemon.js` by name (src/daemon/start.ts:102)
      # and downloads the group hApp with `curl` (src/utils.ts:69).
      for bin in wdocker:cli.js wdaemon:daemon/daemon.js; do
        makeWrapper ${lib.getExe nodejs_22} "$out/bin/''${bin%%:*}" \
          --add-flags "$dest/wdocker/dist/''${bin#*:}" \
          --prefix PATH : ${lib.makeBinPath [nodejs_22 curl]} \
          --set-default WDOCKER_HOLOCHAIN_BINARY $out/libexec/wdocker/${holochainBinaryName}
      done

      runHook postInstall
    '';

    meta = {
      description = "Moss always-online node (wdocker) with the Holochain binary it expects";
      homepage = "https://github.com/lightningrodlabs/moss/tree/v${mossVersion}/wdocker";
      # Declared in Moss's README (§ License) and wdocker/package.json; the
      # repository has no LICENSE file at its root.
      license = lib.licenses.cal10;
      mainProgram = "wdocker";
      platforms = ["x86_64-linux"];
    };
  })
