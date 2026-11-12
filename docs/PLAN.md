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
- Wallet directory switching, `~/.signet_backups` generations (the device backup and Export wallet
  replace them), importing `~/.tezos-client`, Sparkle.

## Keys and recovery

Keys behave as they do in Signet on the Mac; the iPhone's backup plays the part of the Mac's
backups.

- Wallet files stay in octez-client's format (upstream's `TezosClientStore`, unchanged) inside
  the app container (`<container>/.signet`), with Data Protection `complete`, and **included in
  the device's iCloud / computer backup** (`WalletDirectory`), as `~/.signet` is in the Mac's.
  A backup is protected by Apple's encryption, end to end with Advanced Data Protection on.
- **Mainnet keys on the device are always encrypted** (octez `encrypted:`, as upstream writes
  them), with a password of at least 12 characters (`KeyPolicy`): in a backup, the password is
  what protects the key. Test-network keys may be clear. Session-only paper keys never reach
  the disk. The rule is enforced in the Create and Import screens, the only places keys are
  written; upstream's view model does not know it.
- **Create account**, as on the Mac: a random key of any supported type, tz1 to tz5 (upstream's
  `createWallet`). On mainnet the screen then offers Export wallet.
- **Optionally, a recovery phrase** for tz1 to tz3: shown once, three words checked. Made in
  Swift (`RecoveryPhrase`: system randomness, SHA-256 checksum, the BIP39 English list) so the
  entropy never passes through JavaScript; the key comes from upstream's `keyFromMnemonic` at
  44'/1729'/0'/0' and restores in any BIP39 Tezos wallet. tz4 and tz5 have no standard phrase
  derivation and are not offered one. A candidate to move upstream.
- **Export wallet** saves the octez files (keys and contract aliases, one locked snapshot) as a
  folder through Files, for octez-client, Signet on the Mac, or Import.
- Recovery paths: the device backup; an exported wallet; the phrase, where one was made.
- Later: iCloud Keychain (end-to-end encrypted even without Advanced Data Protection, syncs
  without a full restore) as a further home for encrypted keys. Face ID / passcode can unlock
  the password from the Keychain (this device only) so it need not be typed each time.
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
