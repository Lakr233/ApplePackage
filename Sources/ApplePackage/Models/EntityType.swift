//
//  EntityType.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import Foundation

public enum EntityType: String, Codable, CaseIterable, Hashable, Equatable, Identifiable {
    public var id: Self {
        self
    }

    case iPhone
    case iPad
    case appleTV = "AppleTV"
}

extension EntityType {
    var entityValue: String {
        switch self {
        case .iPhone:
            return "software"
        case .iPad:
            return "iPadSoftware"
        case .appleTV:
            return "tvSoftware"
        }
    }

    var searchEntityValue: String {
        switch self {
        case .iPhone, .iPad:
            return entityValue
        case .appleTV:
            return "software,tvSoftware"
        }
    }

    var metadataPlatformValue: String {
        switch self {
        case .iPhone, .iPad:
            return "enterprisestore"
        case .appleTV:
            return "atv9"
        }
    }
}
