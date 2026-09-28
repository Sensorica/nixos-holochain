Closes #

## What and why

<!-- What the change does, and what the machine does differently afterwards. -->

## Commands run and what they printed

<!-- CONTRIBUTING.md: "Paste the commands you ran and what they printed." At least the two below; add any hand test (a curl, an hc call, a nixos-rebuild on real hardware) with its transcript. -->

```console
$ nix run nixpkgs#alejandra -- .

$ nix flake check --no-build --all-systems

```

## VM tests built

<!-- Every `nix build .#checks.x86_64-linux.<name> -L` your change touches, and its result. A new module ships a new VM test, added to the build list in .github/workflows/ci.yml in the same commit. -->

- [ ] `vmTest...`: passed

## Option reference

- [ ] No option was added, changed or removed.
- [ ] Options changed, and `docs/module-options.md` was regenerated with `cp "$(nix build .#options-doc --print-out-paths)" docs/module-options.md` in the same commit.

## Documentation

- [ ] `docs/` (and `README.md`, if it says anything about this) updated in this PR, or nothing there describes the changed behaviour.
