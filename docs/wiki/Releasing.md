# Releasing

## Versioning

[Semantic Versioning](https://semver.org/): `vMAJOR.MINOR.PATCH`.

## Cutting a release

Releases are cut by pushing a git tag. The version flows from the tag into the
package automatically; the package version is not edited by hand:

```sh
git tag v1.2.0
git push origin v1.2.0
```

Still add a `debian/changelog` entry for the version before tagging, so the
package carries real release notes.

Pushing a `v*.*.*` tag runs the **Release** workflow
(`.github/workflows/release.yml`), which:

1. runs the full **CI** pipeline (ShellCheck, the test suite on Debian 11, 12
   and 13, build, lintian, install smoke test). Nothing is published if any
   of it fails;
2. derives the version from the tag (`v1.2.0` → `1.2.0`);
3. builds the `.deb` with that version;
4. publishes it on a new GitHub Release, with generated notes.

Once the release is published, the **APT repository** workflow
(`.github/workflows/apt-repo.yml`) rebuilds the signed archive from *all*
published releases and deploys it to GitHub Pages, so `apt install
oob-usb-serial` serves the new version right away.

Every push and pull request to `main` runs the same **CI** workflow on its
own, and uploads the built `.deb` as an artifact.

## One-time setup (maintainer)

### APT repository signing

The APT archive is GPG-signed with a key you own:

1. Generate and export the key:

   ```sh
   ./scripts/setup-apt-signing-key.sh
   ```

   This writes the **public** key to `docs/apt/pubkey.gpg` (commit it) and the
   **private** key to a local file (never commit it).

2. Add the private key as the `APT_GPG_PRIVATE_KEY` Actions secret (the
   script prints the exact `gh secret set` command), then delete the local
   private key file.

3. Enable GitHub Pages: **Settings → Pages → Source: GitHub Actions**.

### Wiki

1. Enable the wiki: **Settings → Features → Wikis**.
2. Save any first page once in the web UI; GitHub only creates the wiki's git
   repository then.

From then on, the **Wiki** workflow (`.github/workflows/wiki.yml`) mirrors
`docs/wiki/` to the wiki on every change to `main`.
