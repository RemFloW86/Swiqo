# PullOver Pro for iOS 26 (rootless)

Pin any app to a small handle on the side of the screen and pull it over
whatever you're doing, live.

This is c1d3r's PullOver Pro, based on Jond-ie's iOS 15-27 rootless port, with
extra fixes for iOS 26 / Dopamine 3 / ElleKit:

- The window is attached to SpringBoard's real `UIWindowScene` and retries
  until the scene exists (the usual reason the handle stayed invisible).
- The handle is made visible after launch and after unlock instead of staying
  at `alpha = 0` when the lock-state callback does not fire.
- App scene hosting has fallbacks and exception guards for newer FrontBoard /
  UIKit private APIs.
- The risky `SBHomeHardwareButton`, `SBLockHardwareButton` and
  `SBFluidSwitcherGestureManager` hooks are gone.
- QuickSwitch no longer crashes when there are no recents or favorites.
- If AltList is missing, the favorites row is hidden instead of crashing
  Settings.

## Requirements

- iPhone 11 Pro Max (A13) or another Dopamine 3 compatible device
- iOS 26.0 / 26.0.1, Dopamine 3 rootless, ElleKit
- Rootless package manager (Sileo, Zebra, or Filza)
- AltList is recommended for the favorites picker, not required

Target device for this build: iPhone 11 Pro Max, iOS 26.0.1.

## Install

1. Uninstall every old PullOver Pro package first (c1der 2.1.6, pwnapple
   3.0.0 beta1, or any rootful build). They install a dylib with the same
   name and would conflict.
2. Download the `.deb` from the GitHub Actions artifact.
3. Open it in Sileo, Zebra, or Filza and install it.
4. Respring.

The package ID is `com.pulloverpro.ios26`; the old settings domain is not
reused, so old and new settings cannot collide.

## Build with GitHub Actions

The repository contains `.github/workflows/build.yml`. It installs Theos,
`ldid`, `dpkg`, and the iPhoneOS 16.5 SDK, then builds a rootless `.deb`.

1. Create a new GitHub repository.
2. Upload the **contents** of this folder (including the hidden `.github`
   folder) to the repository. GitHub Desktop or the web uploader both work.
3. Open the **Actions** tab, select **Build rootless .deb**, and press
   **Run workflow** (or just push to `main`).
4. Open the finished run and download the `PullOverPro-iOS26-rootless`
   artifact. Inside is the `.deb`.

Local build on macOS with Theos:

```sh
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

<details>
<summary>If the hidden .github folder did not upload</summary>

GitHub's web uploader sometimes skips folders whose name starts with a dot.
Create the workflow by hand instead:

1. In the repository, open **Add file > Create new file**.
2. Name it exactly `.github/workflows/build.yml`.
3. Paste this and commit:

```yaml
name: Build rootless .deb

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-latest
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install build tools
        run: brew install ldid xz dpkg

      - name: Install Theos
        run: |
          git clone --recursive --depth 1 https://github.com/theos/theos.git "$HOME/theos"
          echo "THEOS=$HOME/theos" >> "$GITHUB_ENV"

      - name: Install iOS SDK
        run: |
          mkdir -p "$THEOS/sdks"
          curl -L --fail -o /tmp/iPhoneOS16.5.sdk.tar.xz \
            https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS16.5.sdk.tar.xz
          tar -xJf /tmp/iPhoneOS16.5.sdk.tar.xz -C "$THEOS/sdks"

      - name: Build package
        run: make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

      - name: Show package
        run: ls -l packages

      - name: Upload .deb
        uses: actions/upload-artifact@v4
        with:
          name: PullOverPro-iOS26-rootless
          path: packages/*.deb
          if-no-files-found: error
```

</details>

## Troubleshooting

Debug logging is enabled in this build. After a respring, the tweak writes to:

```
/var/tmp/pulloverpro.log
```

Useful lines:

- `PullOverPro loaded (ctor)` - the dylib was injected.
- `attached to explicit scene ...` - the window found SpringBoard's scene.
- `visibility enabled=... locked=...` - the window alpha/hidden state.
- `host ... scene=... presenter=...` - app scene hosting.
- `recents from ...` - QuickSwitch data source.

If SpringBoard goes to Safe Mode:

1. Let it enter Safe Mode.
2. Uninstall `com.pulloverpro.ios26` in Sileo/Zebra.
3. Send `/var/tmp/pulloverpro.log` and the newest
   `/var/mobile/Library/Logs/CrashReporter/SpringBoard-*.ips` file.

If the handle does not appear, check the log for `attached to explicit scene`
and `visibility`. If those are present but alpha stays `0`, the device is
probably still considered locked by `SBLockStateAggregator`; the tweak retries
once a second until unlock.

## Credits and licence

PullOver Pro by c1d3r ([@c1d3rdev](https://x.com/c1d3rdev),
[source](https://github.com/c1d3rdev/PullOver-Pro)), released under the
GPL-3.0. iOS 13 support by [@akusio_RR](https://x.com/akusio_RR). iOS 15-27
Rootless and RootHide support by [Jond-ie](https://github.com/Jond-ie).

This port keeps the same GPL-3.0 licence (see `LICENSE`) and the original
credits.
