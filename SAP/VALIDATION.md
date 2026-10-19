# Validation record

Local validation on 2026-10-19, Darwin arm64, Swift 6.4:

- Standalone `AppleSAPTool` debug/release builds passed.
- Parent `ApplePackageTool` and `AppleSAPTool` release builds passed.
- Release CLI matched all **1,024 consecutive + 128 additional fresh-state full signatures** across eight private post-handshake sessions. No session or reference data is included in this repository.
- Swift initialization matched every consumed parameter in eight sessions. E matched 528 blocks. F2 matched eight recorded pairs, 200 random pairs and 8,192 byte-sweep cases.
- Seven public kit tests passed, using an entirely synthetic session, independent complete-signature hashes, F2/E vectors, serialization, negative inputs, and static resource hashes.
- Seven offline ApplePackage request tests passed: exact HTTP body coverage, header encoding, stateful retries/redirects/verification, unsigned compatibility, signing failure, and log redaction.
- A relocated release artifact containing both executables and the resource bundle loaded its tables and reproduced consecutive signatures. OpenSSL is linked statically.
- Malformed Unicode/hex CLI input is rejected; empty bodies and exported logical sessions work.

## Live Apple positive and negative controls

A controlled probe used a newly fabricated `example.invalid` account, random password and random device GUID, with certificate verification enabled. No real account credentials were supplied.

The bag-selected legacy authentication endpoint requires the final slash: `https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/`. Before normalization, the bare path produced unusable 301/204 responses. `Bag.normalizedAuthEndpoint` now preserves the correct path and any routing query. Content-Type, attempt value, GUID generation, and XML serialization were unchanged.

The final probe selected its endpoint through the actual bag path, without an endpoint override:

| Request | HTTP status | Business response |
|---|---:|---|
| Direct SAP signature | 200 | XML plist, `MZFinance.BadLogin.Configurator_message` |
| No signature | 403 | empty |
| Deliberately corrupted tag | 403 | empty |

This positive/negative control supports **acceptance of the correctly signed request into business authentication for the tested context and endpoint**. It is not a successful account login; only invented credentials were used. The earlier modern-native endpoint experiment returned non-business 301/404/204 responses and was not used as acceptance evidence.

The opt-in test prints sanitized observations, never passwords, request bodies, signature blobs, or raw session state. It skips without `APPLEPACKAGE_SAP_PROBE_CONTEXT`. Fresh SAP handshake generation remains outside the signing package.

## Toolchain and packaging

Both manifests require Swift tools 6.2 and Swift 6 language mode. Deployment targets are macOS 15, iOS 18, Mac Catalyst 18, tvOS 18, and visionOS 2. The old Swift 5.4 manifest/compatibility shim were removed. Shared configuration/logging state is protected with `Synchronization.Mutex`.

CI and release builds use `macos-latest` with the runner's default Xcode. They do not install or select Xcode; actual OS/Xcode/Swift versions are printed in each job. Release archives contain both executables and the static resource bundle.
