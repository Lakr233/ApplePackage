@testable import ApplePackage
import XCTest

final class ApplePackageSearchParsingTests: XCTestCase {
    private struct SearchResponse: Decodable {
        let resultCount: Int
        let results: [Software]
    }

    func testDecodeSearchResults() throws {
        let json = """
        {
          "resultCount": 1,
          "results": [
            {
              "trackId": 123,
              "bundleId": "com.example.app",
              "trackName": "Example App",
              "version": "1.0.0",
              "price": 0,
              "artistName": "Example Studio",
              "sellerName": "Example Studio",
              "description": "A test app",
              "averageUserRating": 4.5,
              "userRatingCount": 42,
              "artworkUrl512": "https://example.com/icon.png",
              "screenshotUrls": ["https://example.com/screen1.png"],
              "minimumOsVersion": "15.0",
              "fileSizeBytes": "1234567",
              "currentVersionReleaseDate": "2026-02-01T12:00:00Z",
              "releaseNotes": "Bug fixes",
              "formattedPrice": "Free",
              "primaryGenreName": "Utilities"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SearchResponse.self, from: json)
        let results = response.results
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.bundleID, "com.example.app")
        XCTAssertEqual(results.first?.name, "Example App")
        XCTAssertEqual(results.first?.id, 123)
    }

    func testDecodeSearchResultsRejectsInvalidPayload() {
        let json = Data("{\"resultCount\":1,\"results\":[{}]}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SearchResponse.self, from: json))
    }
}
