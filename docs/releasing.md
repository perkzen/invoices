# Releasing

```bash
git tag v0.0.2 && git push origin v0.0.2
```

`.github/workflows/release.yml` builds Release, packages a DMG, signs it with the EdDSA
key, writes `appcast.xml` and publishes both on a GitHub release. The tag is the only
source of the version number. The workflow's comments explain the rest.

The image itself is built by `Scripts/make-dmg.sh`, which lays out the mounted window
— fixed size, the app beside the Applications alias — from `Scripts/dmg-settings.py`.
It needs [dmgbuild](https://github.com/dmgbuild/dmgbuild) (`pipx install dmgbuild`),
which the workflow installs for itself. Build one from a local Release build to see
what a release will look like:

```bash
Scripts/make-dmg.sh build/Build/Products/Release/Invoices.app 0.0.0
```

The app's update feed is `…/releases/latest/download/appcast.xml` — GitHub redirects
that fixed path to whichever release is newest, so the URL compiled into the app never
has to change.

## The signing key, once

The EdDSA key pair is the whole of an update's security, since the build is not
notarized. The private key lives in the login keychain of whoever set this up. Sparkle's
tools are on disk after any build:

```bash
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
gh secret set SPARKLE_PRIVATE_KEY < sparkle-private-key.txt
rm -P sparkle-private-key.txt
```

**Keep a backup of that private key.** It is not recoverable, and installed copies of the
app accept only updates signed with it — losing it means replacing every install by hand.
The matching public key is already in `project.yml` as `SUPublicEDKey`.

## Gatekeeper on first install

The DMG is ad-hoc signed, not notarized, so the **first** install is refused on a
double-click: open *System Settings › Privacy & Security*, find the blocked app near the
bottom and choose **Open Anyway**. That applies once. Sparkle verifies its own downloads
against `SUPublicEDKey`, so every update after that is unattended.
