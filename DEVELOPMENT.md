# Development

## Go Backend Distribution

`ApplePackage` does not commit `GoIPAToolBindings.xcframework` into git.

- `Package.swift` uses a remote binary target from GitHub Releases, configured by `GoIPAToolWrapper/bindings-metadata.json`.
- To force local XCFramework linking, generate `Binaries/GoIPAToolBindings.xcframework` and set `APPLEPACKAGE_USE_LOCAL_BINDINGS=1`.

## How To Bump ipatool

### Fastest Path (GitHub Actions)

Run the `Bump ipatool` workflow and input only one field:

- `ipatool_tag` (example: `v2.3.0`)

The workflow updates the pin, rebuilds metadata, runs regression tests, and opens a PR automatically.

### Local Script

1. Ensure `go`, `swift`, `xcodebuild`, `xcrun`, `lipo`, and `python3` are installed.
2. Run:

```bash
./Scripts/update_ipatool.sh
```

To pin a specific version:

```bash
./Scripts/update_ipatool.sh v2.3.0
```

To override the release tag used in metadata:

```bash
./Scripts/update_ipatool.sh v2.3.0 go-ipatool-v2.3.0-custom
```

The update script:

1. bumps `github.com/majd/ipatool/v2` in `GoIPAToolWrapper/go.mod`
2. runs `go mod tidy`
3. rebuilds `Binaries/GoIPAToolBindings.xcframework`
4. creates deterministic `Binaries/GoIPAToolBindings.xcframework.zip`
5. computes `swift package compute-checksum`
6. resolves repository slug in this order: `APPLEPACKAGE_GITHUB_REPOSITORY`, git `upstream`, existing metadata repository, git `origin`
7. updates `GoIPAToolWrapper/bindings-metadata.json`

Commit these files after a bump:

- `GoIPAToolWrapper/go.mod`
- `GoIPAToolWrapper/go.sum`
- `GoIPAToolWrapper/bindings-metadata.json`

`Package.swift` resolves the release repository from `APPLEPACKAGE_GITHUB_REPOSITORY`, then git `upstream`, then git `origin`, then metadata fallback, so forks can consume their own release assets without hardcoded owner names.
For CI/debug overrides, set `APPLEPACKAGE_GITHUB_REPOSITORY=<owner>/<repo>`.
`Scripts/update_ipatool.sh` also honors `APPLEPACKAGE_GITHUB_REPOSITORY` when writing metadata.

Do not commit generated binary artifacts under `Binaries/`.

## GitHub Actions

- `build.yml`: builds local Go XCFramework and runs tests/builds for macOS, Mac Catalyst, iOS, iOS Simulator, tvOS, tvOS Simulator, visionOS, and visionOS Simulator.
- `bump-ipatool.yml`: manual tag-based bump workflow (single required input: `ipatool_tag`) that opens an automated PR.
- `publish-go-bindings.yml`: rebuilds and publishes the binary zip asset to the release tag declared in metadata.
- `sync-ipatool.yml`: checks upstream `majd/ipatool` release tags daily and opens an automated bump PR when a new version is available.
