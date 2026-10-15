//
//  StoreDownloadEndpoint.swift
//  ApplePackage
//
//  Created on 2026/6/12.
//

import Foundation

/// MZFinance product download endpoints. `volumeStore` is the primary endpoint,
/// but Apple intermittently rejects it (failureType 5002) or answers with no
/// items; the `redownload` dispatch endpoint serves the same payload and is used
/// as fallback, and `update` covers pinned versions redownload cannot serve.
/// The fallback chain mirrors ipatool's sendDownloadProduct.
enum StoreDownloadEndpoint {
    case volumeStore
    case redownload
    case update

    /// The failureType returned by `volumeStore` that signals callers to retry
    /// with the `redownload` endpoint.
    static let retryableFailureType = "5002"

    /// The two endpoints name the external version ID differently in the payload.
    var externalVersionIDKey: String {
        switch self {
        case .volumeStore:
            return "externalVersionId"
        case .redownload, .update:
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
        case .update:
            comps.host = "downloaddispatch.itunes.apple.com"
            comps.path = "/up/updateProduct"
        }
        if let deviceIdentifier {
            comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        }
        return try comps.url.get()
    }
}
