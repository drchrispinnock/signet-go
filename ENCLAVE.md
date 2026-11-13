# Secure Enclave key storage

What Signet (the Mac app, `upstream/`) needs so that software keys can be held on one machine
only, sealed by the Secure Enclave and opened with Touch ID / Face ID for every signature. It
is built in the Mac app first; Signet Go (iOS) then takes it unchanged through the submodule.

Decided (2026-11-13): no files are shared from the Mac to the iOS app, and Signet Go does not
keep keys in iCloud (no iCloud backup of keys, no iCloud Keychain). Keys stay on the device
they were made or imported on; recovery is by recovery phrase or by an encrypted export.

## What the Enclave does and does not do

- The Secure Enclave only holds **P-256** keys. It cannot hold tz1 (Ed25519), tz2 (secp256k1),
  tz4 (BLS) or tz5 keys. So it is not where Tezos keys live: it is the **lock on them**.
- Each sealed account has its own Enclave P-256 key, made inside the Enclave and never
  exportable. The account's Tezos secret key is encrypted to that key (ECIES) and the
  ciphertext is kept in the Keychain. Opening it needs the Enclave and the user's presence
  (biometrics or the device password), checked by the Enclave, not by our code.
- The ciphertext is useless off the machine. Backups of `~/.signet` and Time Machine copies
  hold no key material for a sealed account.
- **Limit, stated plainly:** the secret is still decrypted into memory and passed to the
  Taquito bridge (JavaScriptCore) to sign, so the Enclave protects keys at rest, not while
  signing. Only Enclave-native tz3 keys (phase 2) never leave the Enclave.

## Phase 1: sealed software keys

### Locator and key kind

- New `secret_keys` locator: `signet-sealed:<tz address>` (the address, not the alias, so a
  rename touches nothing in the Keychain).
- New `KeyKind.sealed`, parsed from that scheme; `canSign` includes it.
- `public_keys` / `public_key_hashs` are written as today (clear public key), so octez-client
  still lists the alias and can watch it. octez-client cannot sign with a sealed alias: it
  rejects the unknown scheme, as it would a remote signer it cannot reach. Say so in the UI
  where the Mac app talks about octez-client compatibility.

### `SecretVault` (new, `Signet/Services/SecretVault.swift`)

```swift
protocol SecretVault: Sendable {
    /// Whether sealing works here (Enclave present and the app's entitlements allow it).
    var isAvailable: Bool { get }
    /// Makes an Enclave key for `address`, encrypts `secretKey` (base58, clear) to it, stores the
    /// ciphertext. Fails if an item for `address` exists.
    func seal(secretKey: String, for address: Address) throws
    /// Asks for biometrics / the password (`reason` is shown), then decrypts. Never cached.
    func open(for address: Address, reason: String) async throws -> String
    func contains(_ address: Address) -> Bool
    /// Deletes the ciphertext and the Enclave key (crypto-erase).
    func remove(_ address: Address) throws
}
```

- `EnclaveVault` (behind `#if canImport(Security) && canImport(LocalAuthentication)`):
  - Enclave key: `SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave`, P-256,
    `kSecAttrIsPermanent`, a tag `org.tezos.signet.sealed.<address>`, and
    `SecAccessControlCreateWithFlags(kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    [.privateKeyUsage, .userPresence])`.
  - Encrypt with the public key, algorithm
    `.eciesEncryptionCofactorVariableIVX963SHA256AESGCM`.
  - Ciphertext: a `kSecClassGenericPassword` item (service `org.tezos.signet.sealed`, account
    = address), `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable =
    false`, `kSecUseDataProtectionKeychain = true` (on the Mac; the default on iOS).
    *ThisDeviceOnly* keeps it out of iCloud Keychain, out of backups and off a new device.
  - `open`: a **fresh `LAContext` each call**, `localizedReason` set,
    `touchIDAuthenticationAllowableReuseDuration = 0`; evaluate
    `.deviceOwnerAuthentication` with `await`, then pass the context as
    `kSecUseAuthenticationContext` when fetching the private key, so the decrypt does not
    prompt again (and never blocks the main thread). One prompt per signature, every time.
- `InMemoryVault` for previews and tests (no prompts). Upstream's tests must not need an
  Enclave; the simulator and CI have none.
- Linux (signet-gtk): no `EnclaveVault`; `isAvailable` is false and sealed aliases show as
  "Key not on this machine". Check with signet-gtk that the new kind compiles there.

### `WalletStore` and the view model

- `TezosClientStore` stays file-only: it writes the `signet-sealed:` locator like any other.
  `WalletViewModel` gets a `vault: any SecretVault` (injected, like `walletStore`).
- **`signingKey(for:passphrase:)` becomes `async`.** For `.sealed`:
  `let secret = try await vault.open(for: wallet.address, reason: …)`, then
  `.secret(secret, passphrase: nil, address: wallet.address)`. The `reason` names the action
  ("Sign a transfer of 12 ꜩ to tz1…"): pass it down from each caller.
  Call sites (all in `WalletViewModel*.swift`): send, tokens, staking, delegation, reveal,
  proof of possession, sign payload / ownership proof (line ~1306), multisig sign / propose /
  execute, and the `signer:` closure at ~681 (its type must become `async`). The shielded
  call sites only need to compile.
- `exportSecretKey`: for `.sealed`, open with the vault (prompt), then always encrypt with a
  password (`KeyGenerator.encrypt`) for export; never write a clear key out.
- Removal (`removalSnapshot` / `remove`): for `.sealed`, confirm with the vault prompt instead
  of a password, remove the alias from the files **and** `vault.remove(address)`. Order:
  files first under the store lock, then the vault, so a failure never leaves an alias whose
  key is gone without saying so; on vault failure, report it.
- `load()`: a `.sealed` alias whose address is not in the vault (another Mac, a restored
  backup, a reinstalled phone) is shown as **"Key not on this Mac"**, signing disabled, with
  "Restore from phrase / import" offered. Not an error, not watch-only silently.

### Creating, importing, moving

- Create and Import: "Keep in the Secure Enclave" option, **on by default when
  `vault.isAvailable`**. Imported encrypted keys (`edesk…`) are decrypted once with their
  password, then sealed in clear; the password is not kept.
- Existing accounts: "Move to Secure Enclave…" (prompt for the password if encrypted, seal,
  replace the locator, write). Warn that older copies of the key remain in
  `~/.signet_backups` and Time Machine, and offer to delete Signet's own backup generations.
- Moving out: "Export" (encrypted) and re-import is enough; no "unseal in place" needed.
- Recovery is the user's: a sealed key exists on one machine only. Show this when sealing and
  steer to a recovery phrase (tz1–tz3) or an encrypted export (tz4, tz5). (Signet Go will
  *require* one of the two on mainnet; the Mac may only warn.)

### The Mac-specific catch: entitlements

- Enclave keys and the data-protection Keychain need the `keychain-access-groups` entitlement
  (plus `com.apple.application-identifier` / team), which **requires a provisioning profile**.
  Without it every call fails with `errSecMissingEntitlement` (-34018).
- Today Signet builds ad hoc (`CODE_SIGN_IDENTITY: "-"`) and releases with Developer ID and no
  profile. Needed:
  - a **Developer ID provisioning profile** for the app id, embedded in release builds
    (`release.sh` and `.github/workflows/release.yml`: profile as a repository secret);
  - local builds signed with Apple Development and team `CP8YGC8C4P` to test the vault;
  - entitlement `keychain-access-groups = [$(AppIdentifierPrefix)org.tezos.signet]` (or the
    real bundle id) in `Signet.entitlements`.
- Ad-hoc builds keep working: `isAvailable` is false (detect by trying a throwaway Enclave
  key and catching -34018 or `SecureEnclave.isAvailable == false`), the option is hidden.
- Hardware: Apple Silicon and Intel Macs with a T2. Some Macs that run macOS 15 have no T2
  (e.g. 2019 iMacs): `isAvailable` false there too.
- Sparkle updates must keep the same team: the Keychain items belong to the team's access
  group, so a different signing team would lose access to every sealed key.
- Info.plist: `NSFaceIDUsageDescription` is needed on iOS (Signet Go adds it); the Mac needs
  nothing for Touch ID.

### Tests

- `KeyKind` parses `signet-sealed:`; `canSign` true.
- With `InMemoryVault`: create sealed, sign, rename (vault untouched), remove (vault item
  gone), export (encrypted only), load with missing vault item → "not on this machine".
- `TezosClientStore` round-trips the locator; octez-format files contain no secret for a
  sealed alias (assert the `secret_keys` file has no `edsk`/`spsk`/`p2sk`/`BLsk`).
- Manual on a signed build: Touch ID prompt per signature, cancel → no operation sent,
  ad-hoc build hides the option, a second Mac shows "Key not on this Mac".

## Phase 2 (later): Enclave-native tz3

- An account whose P-256 key is the Enclave key itself: locator `signet-enclave:<tag>`,
  `KeyKind.enclave`. The secret never exists outside the Enclave and is never in JavaScript.
- Signing: the bridge forges and returns the watermarked bytes' Blake2b-256 digest; Swift
  signs it with `SecKeyCreateSignature(.ecdsaSignatureDigestX962SHA256)` (the digest is used
  as is), converts DER to raw r‖s, and returns a `p2sig`. Check against octez whether a low-S
  form is required.
- Not exportable and not recoverable: use it for spending accounts, or as a multisig signer
  with a phrase key as co-signer (the recovery path in `docs/PLAN.md`).

## Then, in Signet Go

Bump the submodule, then: inject `EnclaveVault`, require a phrase or an export for mainnet
accounts, drop the 12-character device password rule (`KeyPolicy` applies to exports), add
`NSFaceIDUsageDescription`, migrate any `secret_keys` entries on the phone into the vault on
first launch, and update "Keys and recovery" in `docs/PLAN.md`.
