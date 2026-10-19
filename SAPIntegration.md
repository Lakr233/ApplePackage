# SAP-signed authentication

ApplePackage can sign authentication requests with `AppleSAPKit` when given a
complete original `post_handshake` JSON context. A fresh SAP handshake is not
implemented. No recorded context is selected automatically, and ordinary calls
without a signer retain their unsigned behavior.

## Command line

Build and run the login command with your own context:

```sh
swift run ApplePackageTool login 'you@example.com' 'YOUR_PASSWORD' \
  --sap-context /absolute/path/to/post-handshake.json
```

When Apple requests a verification code, an interactive terminal prompts for
it and continues with the same signer and advanced random state. In a
noninteractive process, supply the code up front:

```sh
swift run ApplePackageTool login 'you@example.com' 'YOUR_PASSWORD' \
  --sap-context /absolute/path/to/post-handshake.json \
  --code 123456
```

`--sap-iv-address` accepts a decimal or hexadecimal virtual address. Its default
is `0x5000007fed90`, the layout used by the reconstructed signer. Supply the
address corresponding to the saved context if its original layout differs.
This is a salt in the recovered algorithm, not a host pointer to dereference.

The input file supplies the encoded handle, heap, writable-data/RNG state, and
allocator metadata. The command does not generate that state or update the
input file. Starting a new process from the same file creates a new signer
from the original state; it does not resume the previous process's RNG cursor.

## Library injection

```swift
import ApplePackage
import AppleSAPKit
import Foundation

let signer = try SAPSigner(snapshot: Data(contentsOf: contextURL))
let account = try await Authenticator.authenticate(
    email: email,
    password: password,
    code: verificationCode,
    sapSigner: signer
)
```

Retain the same signer if a verification-code challenge requires another
`authenticate` call. Redirects and internal retries already retain it. The
optional parameter is also available on `rotatePasswordToken`.

`SAPRequestSigning` supports another implementation or an injected test double.
Its async `sign(Data)` operation receives the exact final XML request body.
The request sends the returned bytes as base64 in
`X-Apple-ActionSignature`; the body is not serialized again after signing.
Verbose request and response logging redacts signature headers.

## Offline verification

```sh
swift test --filter SAPAuthenticationRequestTests
```

These tests require no account and open no socket. They run the actual
AsyncHTTPClient body producer into memory, compare its bytes with a recording
signer, check header encoding, and exercise repeated/redirected/verification
requests with one stateful signer. They also cover unsigned calls, signing
failure, and signature-header redaction. The SAP package has separate
algorithm/reference-vector checks.

To run the request tests together with the public synthetic/resource/input
validation tests, using the same selection as CI:

```sh
swift test --filter 'SAPAuthenticationRequestTests|SAPSyntheticTests|SAPValidationTests'
```

The release archive includes `ApplePackageTool`, `AppleSAPTool`, and their
shared `ApplePackage_AppleSAPKit.bundle`. Keep that resource bundle next to the
executables when moving or installing them.

## Explicitly enabled live observation

`SAPLiveProbeTests` skips by default. A developer can explicitly provide a
private context to send one invented-account request through the real
AsyncHTTPClient request path:

```sh
APPLEPACKAGE_SAP_PROBE_CONTEXT=/private/path/to/post-handshake.json \
  swift test --filter SAPLiveProbeTests
```

Add `APPLEPACKAGE_SAP_PROBE_CONTROLS=1` to send unsigned and corrupted-tag
controls as well, for a maximum of three variants. Redirects share a total
budget of three, and each destination must use HTTPS on an Apple domain. The
probe uses normal certificate verification, a random GUID, and an invented
`example.invalid` account; it does not load saved account credentials or a
system MAC address. It prints only sanitized response summaries. Contexts,
credentials, request bodies, and signatures must stay out of the repository.

A matching offline signature establishes reconstruction compatibility with
the recorded native reference. It does not establish that Apple accepts a new
live session or that account authentication succeeds. A live test must report
protocol/signature rejection separately from an ordinary authentication error;
receiving an HTTP response alone is insufficient evidence.
