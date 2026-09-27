# Releasing

A release is a git tag on `main`. Pushing a tag `vX.Y.Z` or `vX.Y.Z-rc.N` starts `.github/workflows/release.yml`, which:

1. rejects any other tag shape, and fails unless `CHANGELOG.md` has a `## [X.Y.Z]` (or `## [X.Y.Z-rc.N]`) section with content;
2. runs every job of `.github/workflows/ci.yml` against the tagged commit, VM tests included (about 25 minutes);
3. creates the GitHub release for the tag, with that CHANGELOG section as its text. An `-rc.N` tag becomes a prerelease, which is never shown as the latest release.

Nothing is built or uploaded: consumers pin the tag itself, as `github:Sensorica/nixos-holochain/vX.Y.Z`. If step 1 or 2 fails, no release is created and the tag can be deleted and pushed again once the cause is fixed.

## Versions

SemVer on the public surface named at the top of `CHANGELOG.md`. Below 1.0.0, a minor version may break it, and every such change goes under `### Breaking` in that version's section. A release candidate `vX.Y.Z-rc.N` precedes each minor that a real fleet depends on.

## Cut a release candidate

1. On a branch, move the entries under `## [Unreleased]` into a new section below it, `## [0.1.0-rc.1] - YYYY-MM-DD`, and leave `## [Unreleased]` empty above it. Update the link references at the foot of the file (see below). Open a PR and merge it.
2. Check the notes the release will carry, from an up to date `main`:

   ```bash
   git switch main && git pull --ff-only
   sh scripts/changelog-section.sh 0.1.0-rc.1
   ```

3. Tag the merge commit and push the tag:

   ```bash
   git tag -a v0.1.0-rc.1 -m "v0.1.0-rc.1"
   git push origin v0.1.0-rc.1
   ```

4. Watch the run under Actions, "Release". When it is green, the prerelease is on the Releases page.

To rehearse before tagging, run the workflow by hand from the Actions tab ("Release", "Run workflow") with the tag name as input. It checks the tag shape, prints the notes in the run summary and runs CI on the chosen branch, and publishes nothing.

## Cut a release

The same four steps with `0.1.0` in place of `0.1.0-rc.1`. The `## [0.1.0]` section lists everything since the previous final release, so someone upgrading from it reads one section; the candidate sections stay below it as history.

## Link references

Each version heading is a link, defined at the foot of `CHANGELOG.md`:

```markdown
[Unreleased]: https://github.com/Sensorica/nixos-holochain/compare/v0.1.0-rc.1...HEAD
[0.1.0-rc.1]: https://github.com/Sensorica/nixos-holochain/releases/tag/v0.1.0-rc.1
```

From the second tag on, a version links to the comparison with the one before it, for example `compare/v0.1.0-rc.1...v0.1.0-rc.2`.
