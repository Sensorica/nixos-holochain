# The Holochain HTTP gateway, built from the tagged source of
# github.com/holochain/hc-http-gw (crate `holochain_http_gateway`, binary
# `hc-http-gw`).
#
# There is one gateway release line per Holochain line and the two are not
# interchangeable: the gateway speaks the conductor's admin and app websocket
# protocols through `holochain_client`, so a 0.4.x gateway cannot talk to a
# 0.6 conductor. The mapping is the upstream README's compatibility table,
# cross-checked against each tag's Cargo.toml.
#
# This is deliberately not the `hc http-gw` bundled with holonix's `hc`, which
# carries whatever version that `hc` build was cut with (0.3.1 in the pinned
# holonix) regardless of the conductor line (ADR-009 as amended).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  perl,
  cmake,
  go,
  openssl,
  # The Holochain line to build the gateway for: "0.7" or "0.6".
  line ? "0.7",
}: let
  releases = {
    # holochain_client 0.9.0, holochain_types 0.7.0, edition 2024.
    "0.7" = {
      version = "0.4.0";
      srcHash = "sha256-f+Ub145g4ceWun3/lVwL+bschyHaKpXSbkVRJmJG3pI=";
      cargoHash = "sha256-CKaf0XFwKCqfCimMSuR2ieYDNSwTxaBUQycZ7tkQUjs=";
    };
    # holochain_client 0.8.3, holochain_types 0.6.3, edition 2021.
    "0.6" = {
      version = "0.3.5";
      srcHash = "sha256-og5O4T/EM3eUNaA1UiQaEGFnH3U0saEPWzrj0R31oyQ=";
      cargoHash = "sha256-rF4vAqxbz3WEeXcnj7so/gSlGO35EbXeXC3OxhvTO0M=";
    };
  };

  release =
    releases.${line}
    or (throw "holochain_http_gateway: no release known for Holochain line ${line}");
in
  rustPlatform.buildRustPackage {
    pname = "holochain_http_gateway";
    inherit (release) version cargoHash;

    src = fetchFromGitHub {
      owner = "holochain";
      repo = "hc-http-gw";
      rev = "v${release.version}";
      hash = release.srcHash;
    };

    # perl and pkg-config are openssl-sys' requirements; cmake and go come
    # from the crate's own devShell (transitive C dependencies of the
    # Holochain client stack). bindgenHook exports the LIBCLANG_PATH that
    # devShell sets by hand.
    nativeBuildInputs = [
      pkg-config
      perl
      cmake
      go
      rustPlatform.bindgenHook
    ];

    buildInputs = [openssl];

    # The crate's tests start a real conductor through sweettest, which a
    # sandboxed build has neither the network nor a keystore for. The gateway
    # is covered end to end by the vmTestGateway NixOS test instead.
    doCheck = false;

    meta = {
      description = "HTTP gateway bridging web clients to a Holochain conductor";
      homepage = "https://github.com/holochain/hc-http-gw";
      license = lib.licenses.asl20;
      mainProgram = "hc-http-gw";
      platforms = lib.platforms.linux;
    };
  }
