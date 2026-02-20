//
//  Download.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import ApplePackage
import ArgumentParser
import Foundation

struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Download an app"
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(help: "Email address")
    var email: String

    @Argument(help: "Bundle ID")
    var bundleID: String

    @Option(help: "Version ID")
    var versionID: String?

    @Option(help: "Output path")
    var output: String

    func run() async throws {
        globalOptions.apply()
        try await Configuration.withAccount(email: email) { account in
            try await Authenticator.rotatePasswordToken(for: &account)
            guard let country = Configuration.countryCode(for: account.store) else {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported store identifier: \(account.store)"])
            }
            let app = try await Lookup.lookup(bundleID: bundleID, countryCode: country)
            let downloadOutput = try await ApplePackage.Download.download(account: &account, app: app, externalVersionID: versionID ?? "")

            let url = URL(string: downloadOutput.downloadURL)!
            let outputURL = URL(fileURLWithPath: output)

            let (contentLength, supportsRanges) = try await getContentInfo(from: url)
            print("downloading \(app.name) (\(app.bundleID)) version \(downloadOutput.bundleShortVersionString)")
            print("content length: \(formatBytes(contentLength))")

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputURL.lastPathComponent)

            var startByte: Int64 = 0
            if FileManager.default.fileExists(atPath: tempURL.path) {
                let existingSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0
                if existingSize > 0, existingSize < contentLength, supportsRanges {
                    startByte = existingSize
                    print("found partial download, resuming from \(formatBytes(startByte))")
                } else if existingSize >= contentLength {
                    print("file already downloaded completely")
                } else {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }

            if startByte < contentLength {
                try await downloadWithProgress(from: url, to: tempURL, startByte: startByte, totalSize: contentLength)
            }

            print("writing signature...")
            try await SignatureInjector.inject(
                sinfs: downloadOutput.sinfs,
                iTunesMetadata: downloadOutput.iTunesMetadata,
                into: tempURL.path
            )

            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: outputURL)

            print("saved to \(outputURL.path)")
        }
    }

    private func getContentInfo(from url: URL) async throws -> (contentLength: Int64, supportsRanges: Bool) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "InvalidResponse", code: 0, userInfo: nil)
        }

        let contentLength = httpResponse.expectedContentLength
        let supportsRanges = httpResponse.allHeaderFields["Accept-Ranges"] as? String == "bytes"

        return (contentLength, supportsRanges)
    }

    private func downloadWithProgress(from url: URL, to fileURL: URL, startByte: Int64, totalSize: Int64) async throws {
        var request = URLRequest(url: url)

        if startByte > 0 {
            request.setValue("bytes=\(startByte)-", forHTTPHeaderField: "Range")
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ... 299 ~= httpResponse.statusCode || httpResponse.statusCode == 206
        else {
            throw NSError(domain: "HTTPError", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: nil)
        }

        let fileHandle: FileHandle
        if startByte > 0, FileManager.default.fileExists(atPath: fileURL.path) {
            fileHandle = try FileHandle(forWritingTo: fileURL)
            try fileHandle.seek(toOffset: UInt64(startByte))
        } else {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
            fileHandle = try FileHandle(forWritingTo: fileURL)
        }

        defer {
            try? fileHandle.close()
        }

        var downloadedBytes: Int64 = startByte
        var lastProgressUpdate = Date()
        let progressUpdateInterval: TimeInterval = 0.5

        print("", terminator: "")

        for try await byte in asyncBytes {
            let data = Data([byte])
            try fileHandle.write(contentsOf: data)
            downloadedBytes += 1

            let now = Date()
            if now.timeIntervalSince(lastProgressUpdate) >= progressUpdateInterval {
                updateProgress(downloaded: downloadedBytes, total: totalSize)
                lastProgressUpdate = now
            }
        }

        updateProgress(downloaded: downloadedBytes, total: totalSize)
        print("")
    }

    private func updateProgress(downloaded: Int64, total: Int64) {
        let percentage = min(100.0, Double(downloaded) / Double(total) * 100.0)
        let progressBarWidth = 30
        let filledWidth = Int(Double(progressBarWidth) * percentage / 100.0)
        let emptyWidth = progressBarWidth - filledWidth

        let progressBar = String(repeating: "█", count: filledWidth) + String(repeating: "░", count: emptyWidth)

        print("\rprogress: [\(progressBar)] \(String(format: "%.1f", percentage))% (\(formatBytes(downloaded))/\(formatBytes(total)))", terminator: "")
        fflush(stdout)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0

        while size >= 1024, unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(size)) \(units[unitIndex])"
        } else {
            return String(format: "%.1f \(units[unitIndex])", size)
        }
    }
}
