# UI implementation and build validation — 2026-10-25

## Passed

- macOS production build: `swift build -c release`.
- Navigation regression harness: `./scripts/test_navigation.sh`. Checks distinct search tab identities, query/type restoration, deduplication, neighbour selection after closing a tab, last-tab protection and route restoration. It executes production navigation and filter code with inert page identity fixtures.
- Android release: `:app:assembleRelease`, including Kotlin compilation and vital release lint, against `/tmp/epo-android-ui-check`.
- macOS packaging: ad-hoc app signing, strict signature verification, PKG creation, payload extraction, strict signature verification of the extracted app, version 2.5 and arm64 executable inspection.
- HTML concept: narrow layout, empty search results, clearing the query and dark-mode switching in the in-app browser. Screenshot: `preview-dark.png`.
- `git diff --check`.

## Build outputs

- `dist/EpoBrowser-2.5.pkg`: macOS installer; installs into `/Applications`.
- `dist/EpoBrowser-2.5-macOS.zip`: portable app archive.
- `dist/EpoBrowser-1.2.apk`: Android release APK, signed with the project's configured debug keystore for personal use.
- Runnable macOS app: `~/Library/Caches/EpoBrowser-UIReview/EpoBrowser.app`.

macOS target is Apple silicon, macOS 26 or later. The app has a local ad-hoc signature; the installer has no Developer ID signature or notarization. Android minimum SDK is 26. Existing distribution artifacts are preserved. No installation into `/Applications` or onto an Android device was performed. The release step publishes these artifacts to GitHub and updates `dist/latest.json` to 2.5 (16).

## Limits and environment

Native visual layout, login, streaming, speech/translation, download URL resolution, VoiceOver/TalkBack and device size/font scaling remain unverified. External account-page contents continue to be provided by the connected site.

This Command Line Tools installation lacks XCTest; the attempted XCTest target was removed and replaced by the passing standalone regression harness. Existing linker search-path, Android SDK XML and Gradle deprecation warnings remain. Android's existing List icon also has a deprecation warning.

Final release packaging uses `make_pkg.sh`, a local staging volume, the existing postinstall script and non-relocatable installation into `/Applications`. Its extracted payload and app signature passed verification. Previous versions remain preserved. Git occasionally reports an AppleDouble `._` pack-index warning; no Git metadata was modified.
