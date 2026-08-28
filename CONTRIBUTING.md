# Contributing

This repository is a set of NixOS modules other people are meant to run on their own hardware, so the bar is that a change is *shown* to work, not argued to. Everything below is about that.

## Before you write anything

Open an issue describing what you want to add or change. For a new module or a new option it helps to say what the machine should end up doing, and how you would tell whether it did.

## The loop

1. Fork, and branch from `main`.
2. Make the change.
3. Format every `.nix` file you touched with [alejandra](https://github.com/kamadorueda/alejandra): `nix run nixpkgs#alejandra -- .`
4. Check the flake still evaluates: `nix flake check --no-build --all-systems`
5. Build the VM tests your change touches (see below).
6. Regenerate the option reference if you changed any option (see below).
7. Open a PR. Paste the commands you ran and what they printed.

## Every new module needs a VM test

A module is not finished when it evaluates. `nix flake check --no-build` proves that the Nix expression is well typed; it proves nothing about whether the service starts, whether the binary takes the flags the module passes it, or whether the port is open. All three have been wrong here before.

So: a module that creates a service ships a `pkgs.nixosTest` under `checks` in `flake.nix`, and that test asserts the behaviour, not the configuration. Concretely, prefer

- `machine.wait_for_unit(...)` and `systemctl is-active` over reading the generated unit file,
- a request that returns real data over a listening socket,
- an assertion on a value the service produced over an assertion on a value the module wrote.

Where the sandbox genuinely cannot run the thing (no network, no registry), assert what the module generates, say so in a comment, and exercise the real thing by hand with the transcript in the PR. `vmTestWindtunnel` is the worked example of that compromise.

Add the new check to the build list in `.github/workflows/ci.yml` in the same commit.

Run a single test with:

```bash
nix build .#checks.x86_64-linux.<name> -L
```

These need KVM. On a machine without it they will be extremely slow rather than failing outright.

## The option reference is generated

`docs/module-options.md` is built from the module declarations by `nix build .#options-doc`. It is committed so that it can be read on the web, and CI fails when the committed copy differs from a fresh build. Hand-editing it is therefore always wrong: the next CI run will say so.

After changing, adding or removing any option:

```bash
cp "$(nix build .#options-doc --print-out-paths)" docs/module-options.md
```

in the same commit as the option change. Two things make the difference between a clean regeneration and a noisy one:

- Give any option whose default is a package, a path, or anything else that lands in the Nix store a `defaultText` (`lib.literalExpression` or `lib.literalMD`). Without it the store path is written into the document and every unrelated commit rewrites it.
- Write the description as the answer to "what does this do, and what happens if I get it wrong", not as a restatement of the option name. It is the only documentation most people will read.

Prose about how the modules fit together belongs in `docs/architecture.md`, not in the generated file.

## Documentation

Update `docs/` in the same PR as the behaviour it describes. `README.md` has a rule of its own: every statement in it has to be true of the tree at that commit, and every ticked roadmap item cites the PR that closed it.

## Commits and PRs

- Conventional commits (`feat(edgenode): …`, `fix(grafana): …`, `docs: …`), one logical change per commit.
- No AI-tool attribution lines in commit messages.
- Nothing binary and nothing secret in git. hApp bundles are fetched by hash with `pkgs.fetchurl`; private keys, tokens and passphrases never enter the repository. Public SSH keys are not secrets and are committed in the example fleet on purpose.
- A PR body says what commands prove the change, and what they printed.

## Licence

By contributing you agree that your work is licensed under AGPL-3.0, the same as the rest of the repository.
