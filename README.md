# ApplePackage

A Swift package and command-line tool for managing Apple apps, including searching, downloading, and authenticating with Apple services.

## Features

- **Authentication**: Login and logout from Apple accounts
- **Search**: Search for apps in the App Store
- **Download**: Download apps using your Apple account
- **Versions**: Retrieve version information for apps

## Installation

### Prerequisites

- Swift 5.9 or later
- macOS 12+

### Using Swift Run

Clone the repository and run the tool directly:

```bash
git clone https://github.com/Lakr233/ApplePackage.git
cd ApplePackage
swift run ApplePackageTool <subcommand>
```

For example:

```bash
swift run ApplePackageTool --help
```

## Usage

### Login

Authenticate with your Apple account:

```bash
applepackage login <email> <password> [--code <2fa-code>]
```

- `<email>`: Your Apple ID email address
- `<password>`: Your Apple ID password
- `--code`: Optional 2FA verification code

### Logout

Remove stored credentials for an account:

```bash
applepackage logout <email>
```

- `<email>`: The email address of the account to logout

### Search

Search for apps in the App Store:

```bash
applepackage search <term> [--country <country-code>] [--limit <number>]
```

- `<term>`: Search term
- `--country`: Country code (default: US)
- `--limit`: Maximum number of results (default: 10)

### Versions

List available versions for an app:

```bash
applepackage versions <email> <bundle-id>
```

- `<email>`: Your Apple ID email address
- `<bundle-id>`: The bundle identifier of the app

### Download

Download an app:

```bash
applepackage download <email> <bundle-id> [--version-id <version>] --output <path>
```

- `<email>`: Your Apple ID email address
- `<bundle-id>`: The bundle identifier of the app
- `--version-id`: Optional specific version ID to download
- `--output`: Output path for the downloaded file

## Library Usage

Add ApplePackage as a dependency in your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/Lakr233/ApplePackage.git", from: "1.0.0")
]
```

Import and use:

```swift
import ApplePackage

// Example: Search for apps
let results = try await Searcher.search(term: "example", countryCode: "US", limit: 10)
```

## Dependencies

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation.git)
- [AsyncHTTPClient](https://github.com/swift-server/async-http-client.git)
- [Swift Collections](https://github.com/apple/swift-collections.git)
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This tool is for educational and personal use only. Please respect Apple's terms of service and copyright laws when using this software. We are not responsible if your Apple account gets banned or any other issues arise from using this tool.
