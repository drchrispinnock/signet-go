# Signet Go: plan

Signet Go is the iOS port of [Signet](https://github.com/drchrispinnock/signet), the macOS Tezos
wallet. Android will be a separate port.

## Approach

`upstream/` is the Mac repository (`main`) as a git submodule, as in signet-gtk. Its
`Signet/Models`, `Signet/Services` and `Signet/ViewModels` are compiled **unchanged** into the iOS
app; the views are new, written for iPhone (navigation stacks and tabs, not menus and stacked
sheets), borrowing from upstream's SwiftUI views where they fit. The Xcode project is generated
by XcodeGen from `project.yml`, as upstream's is. Upstream's `SignetTests` should compile against
the iOS app as far as they do not test Mac-only code.

Upstream files that cannot build on iOS get replacements in this repository:

| Upstream | Why | Replacement |
|---|---|---|
| `PublicHTTPClient` | runs `/usr/bin/curl` via `Process` | Network.framework connection to the validated public IP, TLS SNI/hostname validation kept, same byte/time/slot limits |
| `LedgerHID` | IOKit USB HID | stub first; Bluetooth (Nano X, Flex, Stax) later |
| `ImageLoader`, `ArtworkCache`, `QRCode`, `Appearance` | `NSImage`, `NSApp` | UIKit equivalents |
| `UpdaterService` | Sparkle | none: TestFlight / App Store |

## Features

| Area | Phase |
|---|---|
| Create (tz1 to tz5), import (phrase, secret key, fundraiser), session-only paper keys, export, rename, forget | v1 |
| Address book, TzProfiles, `.tez` domains, avatars | v1 |
| Send, Receive (QR), camera QR scanning (addresses, dApp pairing) | v1 |
| Balances with staking breakdown, tokens, activity, NFT grid | v1 |
| Delegate and stake | v1 |
| Networks, custom node, node status, faucet (test networks behind a setting) | v1 |
| dApps (Octez Connect): pairing code, QR, `signet://` links; relay in the foreground only | v1 |
| Etherlink: balance, receive alias, send on layer 2, bridge deposit | v1 or v1.1 |
| NFT transfer, burn, download (to Photos/Files) | v1.1 |
| Expert mode: multisig, baking, governance (layer 1 and Etherlink), proof of possession | later |
| Ledger over Bluetooth | later |
| Secure Enclave (secret wrapping, tz3 device keys) | after the Mac version has it |

**Not included:**

- **Buy** (Mt Pelerin, `BuySheet`, `BuyWebView`): never built into a view. `BuyProvider`,
  `MtPelerin` and `WalletViewModel.buyURL` stay compiled but unreachable.
- **TzEL shielded transactions.** For now option (a): upstream's shielded code is compiled
  (it is threaded through `WalletViewModel`, `ChainService`, `Network`, `AppStateStore` and the
  bridge's `tzel.js`/`shield.js`) but no shielded view exists and shielded transactions are never
  enabled; a test must assert that `shieldedEnabled` stays off on every network. Later, option
  (b): an upstream refactor putting TzEL behind a compilation condition (state out of
  `WalletViewModel` into its own object, the `ChainService` deposit/burn calls into a separate
  protocol, a bridge bundle built without `tzel.js`/`shield.js`), so it is not in the iOS binary.
  TzEL is still changing, which argues for doing that refactor before it grows further.
- Wallet directory switching, `~/.signet_backups`, importing `~/.tezos-client`, Sparkle.

## Keys and recovery

- Wallet files stay in octez-client's format (upstream's `TezosClientStore`, unchanged) inside
  the app container, in a directory excluded from iCloud/iTunes backup
  (`isExcludedFromBackup`) and with Data Protection `complete`.
- New accounts are derived from a BIP39 recovery phrase, shown once and confirmed at creation
  (the bridge needs a `generateMnemonic` beside its existing `validateMnemonic`/`keyFromMnemonic`).
  Taquito derives tz1, tz2 and tz3 from a phrase; tz4 and tz5 are not phrase-recoverable.
- Secrets at rest are octez `encrypted:` entries, as upstream writes them. Face ID / passcode
  can unlock the password from the Keychain (this device only) so it need not be typed each time.
- Recovery paths: the phrase, and export of the password-encrypted wallet to Files (the only
  path for tz4/tz5).
- **Secure Enclave: not yet. It is done in the Mac version first**, then adopted here through
  upstream. Two parts: wrapping stored secrets with an Enclave P-256 key, and Enclave device
  keys (tz3 signed inside the Enclave, never exportable, recoverable only through a multisig
  with a phrase key as co-signer).

## Upstream changes needed

Made in the submodule's working tree so the iOS build works; they belong in the Mac repository
(commit there, then bump the submodule):

- `Signet/Services/TezosClientStore.swift`, `FileManager.userHome`: `#if os(macOS)` for
  `homeDirectoryForCurrentUser` (unavailable on iOS), `NSHomeDirectory()` on other Darwin.
- `SignetTests/TezosClientStoreTests.swift` (`aHeldLockMakesCallersWaitThenFail`) and
  `SignetTests/AuditFixTests.swift` (`shieldedWalletFileIsLockedAgainstOtherProcesses`):
  `#if !os(iOS)`, since they hold the lock from a python3 `Process`.
- `SignetTests/AuditFixTests.swift` (`plainHTTPServicesAreNamed`): `#if !SIGNET_NO_SHIELDED`,
  the first use of the flag that option (b) for TzEL would extend.

Wanted next, so the port need not copy code:

- `ImageLoader` / `ArtworkCache` (and the tests that draw images) on a `PlatformImage`
  typealias (`NSImage` / `UIImage`) rather than `NSImage` directly.
- `PublicHTTPClient`: split the curl transport from the policy (`configuration`, `decode`,
  redirects, gate) so iOS supplies only a Network.framework transport and
  `AuditRepairTests` run here.

Upstream tests not yet compiled here: `ArtworkPolicyTests`, `AvatarTests`, `NFTTests`,
`AuditRepairTests` (waiting on the two items above); `QRCodeTests`, `TestHostIsolationTests`,
`ArtworkCacheTests` (Mac-only code); `UpdaterTests`, `BuyWebViewTests`, `MtPelerinTests`
(never included); `WalletLockMeasurementTests` (opt-in benchmark using python3).

## Open

- App Store: guideline 3.1.5(b) wants wallet apps from developers enrolled as an organization;
  the current account is an individual. TestFlight first; settle enrolment before review.
- TzEL refactor upstream (see above).
