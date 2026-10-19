# Validation record

Local validation on 2026-10-19, Darwin arm64, Swift 6.4:

- Standalone `AppleSAPTool` debug/release builds passed.
- Parent `ApplePackageTool` and `AppleSAPTool` release builds passed.
- Release CLI matched all **1,024 consecutive + 128 additional fresh-state full signatures** across eight private post-handshake sessions. No session or reference data is included in this repository.
- Swift initialization matched every consumed parameter in eight sessions. E matched 528 blocks. F2 matched eight recorded pairs, 200 random pairs and 8,192 byte-sweep cases.
- Seven public kit tests passed, using an entirely synthetic session, independent complete-signature hashes, F2/E vectors, serialization, negative inputs, and static resource hashes.
- Five offline ApplePackage request tests passed: exact HTTP body coverage, header encoding, stateful retries/redirects/verification, unsigned compatibility, signing failure, and log redaction.
- A relocated release artifact containing both executables and the resource bundle loaded its tables and reproduced consecutive signatures. OpenSSL is linked statically.
- Malformed Unicode/hex CLI input is rejected; empty bodies and exported logical sessions work.

## Live Apple observation — acceptance not established

A controlled probe used a newly fabricated `example.invalid` account, random password and random device GUID, with certificate verification enabled. No real account credentials were supplied.

Apple's current bag selected `https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate`.

| Request | HTTP status | Location | Parseable authentication body |
|---|---:|---|---|
| Direct SAP signature | 301 | absent | absent |
| No signature | 204 | absent | absent |
| Deliberately corrupted signature | 301 | absent | absent |

These responses do **not** establish signature acceptance or successful authentication. The signed and corrupted controls are indistinguishable. Endpoint/session validity and server-side behavior remain under investigation; an HTTP response alone is not a pass. Fresh SAP handshake generation is not implemented by this package.

The opt-in test prints sanitized observations, never passwords, request bodies, signature blobs, or raw session state. It skips without `APPLEPACKAGE_SAP_PROBE_CONTEXT`.
