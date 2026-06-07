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

    @Option(help: "Platform to download for: iPhone, iPad, or AppleTV")
    var platform: PlatformArgument?
    

    @Option(help: "Output path")
    var output: String

    func run() async throws {
        globalOptions.apply()
        let outputURL = try validateOutputURL(output)
        let entityType = platform?.entityType ?? EntityType.iPhone

        try await Configuration.withAccount(email: email) { account in
            try await Authenticator.rotatePasswordToken(for: &account)
            guard let country = Configuration.countryCode(for: account.store) else {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported store identifier: \(account.store)"])
            }
            let app = try await Lookup.lookup(bundleID: bundleID, countryCode: country, entityType: entityType)
            let resolvedVersionID = try await resolveVersionID(
                requestedVersionID: versionID,
                app: app,
                country: country,
                entityType: entityType
            )
            let downloadOutput = try await ApplePackage.Download.download(
                account: &account,
                app: app,
                externalVersionID: resolvedVersionID
            )

            let url = URL(string: downloadOutput.downloadURL)!

            let (contentLength, supportsRanges) = try await getContentInfo(from: url)
            print("downloading \(app.name) (\(app.bundleID)) version \(downloadOutput.bundleShortVersionString)")
            print("content length: \(formatBytes(contentLength))")

            let tempURL = temporaryDownloadURL(
                outputURL: outputURL,
                bundleID: app.bundleID,
                bundleVersion: downloadOutput.bundleVersion
            )

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

            try PackagePlatformValidator.ensurePackage(at: tempURL, supports: entityType)

            try replaceOutput(at: outputURL, with: tempURL)

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

        let downloader = ProgressDownloader(
            fileURL: fileURL,
            startByte: startByte,
            totalSize: totalSize,
            progressHandler: updateProgress(downloaded:total:)
        )

        print("", terminator: "")
        try await downloader.download(request: request)
        updateProgress(downloaded: totalSize, total: totalSize)
        print("")
    }

    private func resolveVersionID(
        requestedVersionID: String?,
        app: Software,
        country: String,
        entityType: EntityType?
    ) async throws -> String {
        if let requestedVersionID, !requestedVersionID.isEmpty {
            return requestedVersionID
        }

        guard let entityType else {
            return ""
        }

        let metadata = try await PlatformVersionLookup.lookup(
            appID: app.id,
            countryCode: country,
            entityType: entityType
        )
        return metadata.externalVersionID
    }
}

private final class ProgressDownloader: NSObject, URLSessionDataDelegate {
    private let fileURL: URL
    private let startByte: Int64
    private let totalSize: Int64
    private let progressHandler: (Int64, Int64) -> Void

    private var fileHandle: FileHandle?
    private var continuation: CheckedContinuation<Void, Error>?
    private var downloadedBytes: Int64
    private var lastProgressUpdate = Date()

    init(
        fileURL: URL,
        startByte: Int64,
        totalSize: Int64,
        progressHandler: @escaping (Int64, Int64) -> Void
    ) {
        self.fileURL = fileURL
        self.startByte = startByte
        self.totalSize = totalSize
        self.progressHandler = progressHandler
        downloadedBytes = startByte
    }

    func download(request: URLRequest) async throws {
        try prepareOutputFile()

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
        defer {
            session.finishTasksAndInvalidate()
        }

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.dataTask(with: request).resume()
        }
    }

    private func prepareOutputFile() throws {
        if startByte > 0, FileManager.default.fileExists(atPath: fileURL.path) {
            fileHandle = try FileHandle(forWritingTo: fileURL)
            try fileHandle?.seek(toOffset: UInt64(startByte))
        } else {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
            fileHandle = try FileHandle(forWritingTo: fileURL)
        }
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse,
              200 ... 299 ~= httpResponse.statusCode || httpResponse.statusCode == 206
        else {
            complete(with: NSError(domain: "HTTPError", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: nil))
            completionHandler(.cancel)
            return
        }

        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
            downloadedBytes += Int64(data.count)

            let now = Date()
            if now.timeIntervalSince(lastProgressUpdate) >= 0.5 {
                progressHandler(downloadedBytes, totalSize)
                lastProgressUpdate = now
            }
        } catch {
            complete(with: error)
            dataTask.cancel()
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        complete(with: error)
    }

    private func complete(with error: Error?) {
        try? fileHandle?.close()
        fileHandle = nil

        guard let continuation else {
            return
        }

        self.continuation = nil
        if let error = error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

private extension Download {
    private func validateOutputURL(_ output: String) throws -> URL {
        let outputURL = URL(fileURLWithPath: output).standardizedFileURL

        guard outputURL.pathExtension.caseInsensitiveCompare("ipa") == .orderedSame else {
            throw NSError(
                domain: "InvalidOutputPath",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Output path must end with .ipa"]
            )
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue
        {
            throw NSError(
                domain: "InvalidOutputPath",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Output path must point to an ipa file"]
            )
        }

        let parentURL = outputURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw NSError(
                domain: "InvalidOutputPath",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Output directory does not exist: \(parentURL.path)"]
            )
        }

        try verifyWritableDirectory(parentURL)

        return outputURL
    }

    private func verifyWritableDirectory(_ directoryURL: URL) throws {
        let probeURL = directoryURL.appendingPathComponent(".applepackage-write-test-\(UUID().uuidString)")
        do {
            try Data().write(to: probeURL, options: .withoutOverwriting)
            try FileManager.default.removeItem(at: probeURL)
        } catch {
            try? FileManager.default.removeItem(at: probeURL)
            throw NSError(
                domain: "InvalidOutputPath",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Output directory is not writable: \(directoryURL.path)"]
            )
        }
    }

    private func temporaryDownloadURL(outputURL: URL, bundleID: String, bundleVersion: String) -> URL {
        let parentURL = outputURL.deletingLastPathComponent()
        let identity = [bundleID, bundleVersion]
            .map(sanitizedPathComponent)
            .joined(separator: ".")
        return parentURL.appendingPathComponent(".\(outputURL.lastPathComponent).\(identity).download")
    }

    private func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(scalars)
        return result.isEmpty ? "unknown" : result
    }

    private func replaceOutput(at outputURL: URL, with tempURL: URL) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(
                outputURL,
                withItemAt: tempURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: tempURL, to: outputURL)
        }
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
