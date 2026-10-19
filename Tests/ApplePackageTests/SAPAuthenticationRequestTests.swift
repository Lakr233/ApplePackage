import AsyncHTTPClient
@testable import ApplePackage
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import XCTest

final class SAPAuthenticationRequestTests: XCTestCase {
    private actor RecordingSigner: SAPRequestSigning {
        private var bodies: [Data] = []

        func sign(_ body: Data) throws -> Data {
            bodies.append(body)
            return Data([0xa5, UInt8(bodies.count)])
        }

        func recordedBodies() -> [Data] { bodies }
    }

    private actor FailingSigner: SAPRequestSigning {
        func sign(_: Data) throws -> Data { throw TestError.signingFailed }
    }

    private enum TestError: Error {
        case signingFailed
        case unexpectedBodyChunk
    }

    /// Run the actual AsyncHTTPClient body producer without opening a socket.
    private func bodyData(_ request: HTTPClient.Request) throws -> Data {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let eventLoop = group.next()
        let captured = NIOLockedValueBox(Data())
        let body = try XCTUnwrap(request.body)
        try body.stream(.init { part in
            guard case let .byteBuffer(buffer) = part else {
                return eventLoop.makeFailedFuture(TestError.unexpectedBodyChunk)
            }
            captured.withLockedValue { $0.append(contentsOf: buffer.readableBytesView) }
            return eventLoop.makeSucceededFuture(())
        }).wait()
        let data = captured.withLockedValue { $0 }
        return data
    }

    private func makeRequest(
        endpoint: String = "https://auth.example.invalid/login",
        code: String = "",
        signer: (any SAPRequestSigning)? = nil
    ) async throws -> HTTPClient.Request {
        try await Authenticator.makeRequest(
            endpoint: XCTUnwrap(URL(string: endpoint)),
            email: "reader+ä@example.invalid",
            password: "test<&password",
            code: code,
            cookies: [],
            deviceIdentifier: "00-11-22-33-44-55",
            sapSigner: signer
        )
    }

    func testSignatureCoversExactSerializedHTTPBody() async throws {
        let signer = RecordingSigner()
        let request = try await makeRequest(code: "123456", signer: signer)
        let sentBody = try bodyData(request)
        let signedBodies = await signer.recordedBodies()
        XCTAssertEqual(signedBodies, [sentBody])
        XCTAssertEqual(request.method.rawValue, "POST")
        let signature = try XCTUnwrap(request.headers.first(name: "X-Apple-ActionSignature"))
        XCTAssertEqual(Data(base64Encoded: signature), Data([0xa5, 1]))
        let parameters = try XCTUnwrap(PropertyListSerialization.propertyList(from: sentBody, format: nil) as? [String: String])
        XCTAssertEqual(parameters["appleId"], "reader+ä@example.invalid")
        XCTAssertEqual(parameters["password"], "test<&password123456")
        XCTAssertEqual(parameters["attempt"], "2")
    }

    func testRetryRedirectAndVerificationReuseSignerState() async throws {
        let signer = RecordingSigner()
        let first = try await makeRequest(signer: signer)
        let retry = try await makeRequest(signer: signer)
        let redirect = try await makeRequest(endpoint: "https://pod.example.invalid/login", signer: signer)
        let verification = try await makeRequest(endpoint: "https://pod.example.invalid/login", code: "654321", signer: signer)
        let requests = [first, retry, redirect, verification]
        let sentBodies = try requests.map(bodyData)
        let signedBodies = await signer.recordedBodies()
        XCTAssertEqual(signedBodies, sentBodies)
        XCTAssertEqual(sentBodies[0], sentBodies[1])
        XCTAssertEqual(sentBodies[0], sentBodies[2])
        XCTAssertNotEqual(sentBodies[2], sentBodies[3])
        for (index, request) in requests.enumerated() {
            let header = try XCTUnwrap(request.headers.first(name: "X-Apple-ActionSignature"))
            XCTAssertEqual(Data(base64Encoded: header), Data([0xa5, UInt8(index + 1)]))
        }
    }

    func testUnsignedRequestRemainsAvailable() async throws {
        let request = try await makeRequest()
        XCTAssertNil(request.headers.first(name: "X-Apple-ActionSignature"))
        XCTAssertFalse(try bodyData(request).isEmpty)
    }

    func testSigningFailurePreventsRequestConstruction() async throws {
        do {
            _ = try await makeRequest(signer: FailingSigner())
            XCTFail("Expected signing failure")
        } catch TestError.signingFailed {
            // No request is returned to the HTTP client.
        }
    }

    func testSignatureHeaderIsRedactedCaseInsensitively() {
        XCTAssertEqual(APLogger.safeHeaderValue(name: "X-Apple-ActionSignature", value: "sensitive-blob"), "<redacted>")
        XCTAssertEqual(APLogger.safeHeaderValue(name: "x-apple-actionsignature", value: "sensitive-blob"), "<redacted>")
        XCTAssertEqual(APLogger.safeHeaderValue(name: "X-Token", value: "secret"), "<redacted>")
        XCTAssertEqual(APLogger.safeHeaderValue(name: "Content-Type", value: "application/x-apple-plist"), "application/x-apple-plist")
    }
}
