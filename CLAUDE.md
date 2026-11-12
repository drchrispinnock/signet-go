# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Signet Go**: the iOS port of **Signet**, the macOS Tezos wallet in SwiftUI. Android will be a
separate port. The plan, feature phases and key-storage design are in `docs/PLAN.md`; read it
before adding features.

`upstream/` is the Mac repository (`main`) as a git submodule (HTTPS URL, so a recursive clone
needs no SSH key). Its `CLAUDE.md` documents the shared code in depth (wallet storage and locking,
the Taquito bridge, approved-limits signing, the operation journal, dApp identity rules, multisig);
read the relevant section there before touching anything that uses it. The sibling port
`../signet-gtk` reuses upstream the same way and is the model for how replacements are done.

## How upstream is reused

- Upstream's `Signet/Models`, `Signet/Services` and `Signet/ViewModels` are compiled **as they
  are** into the app. A change the iOS app needs in shared code goes upstream (the user owns
  that repository) and the submodule is bumped. Never commit or push in `upstream/` from here;
  any edit made in its working tree to unblock the build is listed under "Upstream changes
  needed" in `docs/PLAN.md` until it lands upstream.
- Upstream files that need macOS (`PublicHTTPClient`'s `/usr/bin/curl`, `LedgerHID`'s IOKit,
  `NSImage`/`NSApp` users, Sparkle's `UpdaterService`) are excluded and replaced by iOS versions
  in this repository, keeping upstream's type names and API so the rest of the module compiles.
- Views are written new for iPhone; upstream's SwiftUI views are reference, not compiled.

## Never include

- **Buy** (Mt Pelerin / any on-ramp): no view, no web view, no entry point.
- **TzEL shielded transactions**: upstream's code is compiled because it is threaded through
  `WalletViewModel`, but no shielded view is built and shielded transactions must never be
  enabled; keep the test asserting that. See `docs/PLAN.md` for the planned upstream refactor.

## Commands

The Xcode project is generated from `project.yml` by XcodeGen and is not committed
(`SignetGo.xcodeproj` is git-ignored). Edit `project.yml`, then regenerate:

```sh
git submodule update --init      # after cloning
brew install xcodegen            # once
xcodegen generate
```

Build (output is noisy; grep for `error:` or `** BUILD`):

```sh
xcodebuild -project SignetGo.xcodeproj -scheme SignetGo -destination 'generic/platform=iOS Simulator' -derivedDataPath build build
xcodebuild -project SignetGo.xcodeproj -scheme SignetGo -destination 'generic/platform=iOS Simulator' -derivedDataPath build build-for-testing
```

Run the tests on a simulator (needs the iOS simulator runtime, `xcodebuild -downloadPlatform iOS`;
`xcrun simctl list devices available` gives an id). Tests use Swift Testing; select suites,
since function-level `-only-testing` can silently run nothing:

```sh
xcodebuild -project SignetGo.xcodeproj -scheme SignetGo -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath build test
xcodebuild … test -only-testing:SignetTests/NeverIncludedTests
```

Live network tests are opt-in as upstream: `TEST_RUNNER_SIGNET_NETWORK_TESTS=1 xcodebuild … test`.
Running on a device or as "Designed for iPad" on the Mac needs an Apple Development team
(`DEVELOPMENT_TEAM`); ad-hoc signing is refused for the iOS SDK.

## Layout

- `project.yml`: target `SignetGo` (module and product name `Signet`, so upstream's
  `@testable import Signet` tests work; bundle id `org.tezos.signet.go`, display name
  "Signet Go"), compiling `upstream/Signet/{Models,ViewModels,Services}` less the Mac-only
  files listed there, plus `SignetGo/`. Target `SignetTests` compiles `upstream/SignetTests`
  less the excluded files (each with its reason) plus `Tests/SignetGoTests`. Both define
  `SIGNET_NO_SHIELDED`.
- `SignetGo/App`: `SignetGoApp`, the composition root (`makeModel`, after upstream's
  `SignetApp.makeModel`: no backups, no `~/.tezos-client` import, shielded store in memory).
- `SignetGo/Platform`: replacements for Mac-only upstream files, same type names and API
  (`LedgerHID` stub, `PublicHTTPClient` stub that refuses every request) and iOS-only care
  (`WalletDirectory`: file protection for `<container>/.signet`, which is in device backups).
- `SignetGo/Services`: iOS-side logic that is not a replacement: `KeyPolicy` (mainnet keys always
  encrypted, 12-character minimum; apply it wherever a key is written) and `RecoveryPhrase`
  (BIP39 phrases in Swift; candidates to move upstream).
- `SignetGo/Views`: iPhone views. Upstream statics that upstream's tests call keep their
  names and signatures (`SendSheet.capture`).
- `Tests/SignetGoTests`: the port's own tests (`NeverIncludedTests` guards Buy/TzEL staying out).
