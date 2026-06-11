//
//  StoreDownloadEndpoint.swift
//  ApplePackage
//
//  Created on 2026/6/12.
//

import Foundation

/// MZFinance product download endpoints. `volumeStore` is the primary endpoint,
/// but Apple intermittently rejects it with failureType 5002; the legacy
/// `redownload` dispatch endpoint serves the same payload and is used as fallback.
enum StoreDownloadEndpoint {
    case volumeStore
    case redownload

    /// The failureType returned by `volumeStore` that signals callers to retry
    /// with the `redownload` endpoint.
    static let retryableFailureType = "5002"

    /// The two endpoints name the external version ID differently in the payload.
    var externalVersionIDKey: String {
        switch self {
        case .volumeStore:
            return "externalVersionId"
        case .redownload:
            return "appExtVrsId"
        }
    }

    func url(pod: String?, deviceIdentifier: String?) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        switch self {
        case .volumeStore:
            comps.host = Configuration.storeAPIHost(pod: pod)
            comps.path = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"
        case .redownload:
            comps.host = "downloaddispatch.itunes.apple.com"
            comps.path = "/r/redownload"
        }
        if let deviceIdentifier {
            comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        }
        return try comps.url.get()
    }
}
