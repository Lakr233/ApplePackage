//
//  Configuration.swift
//  IPATool
//
//  Created by QAQ on 2023/10/4.
//

import AsyncHTTPClient
import Foundation
import NIOSSL

public enum Configuration {
    /**
     DeviceIdentifier is a unique identifier for your device.

     - On macOS, it is a MAC address and can be read by calling DeviceIdentifier.system.
     - If that fails and throws an error, use DeviceIdentifier.random and **save it**

     **It is a must set value before any network request**
     **otherwise your account may be locked for security reason**
     */
    public nonisolated(unsafe) static var deviceIdentifier: String = (try? DeviceIdentifier.system()) ?? "" {
        didSet {
            assert(!deviceIdentifier.contains(":"))
            assert(!deviceIdentifier.contains("-"))
            assert(!deviceIdentifier.contains(" "))
            assert(!deviceIdentifier.contains("\n"))
        }
    }

    public nonisolated(unsafe) static var userAgent: String = "Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6"

    public nonisolated(unsafe) static var tlsConfiguration: TLSConfiguration = {
        precondition(!deviceIdentifier.isEmpty, "deviceIdentifier must be set")
        #if DEBUG
            var conf = TLSConfiguration.makeClientConfiguration()
            conf.certificateVerification = .none
            return conf
        #else
            return TLSConfiguration.makeClientConfiguration()
        #endif
    }()

    public static let storeFrontValues: [String: String] = kCountryCodes
    public static let timeoutConnect: Int64 = 10
    public static let timeoutRead: Int64 = 30

    #if os(macOS)
        public nonisolated(unsafe) static var homePath: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".ipatool", isDirectory: true)
        {
            didSet { assert(homePath.isFileURL) }
        }
    #else
        public nonisolated(unsafe) static var homePath: URL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(".ipatool", isDirectory: true)
        {
            didSet { assert(homePath.isFileURL) }
        }
    #endif

    public static func storeId(for countryCode: String) -> String? {
        storeFrontValues[countryCode]
    }

    public static func countryCode(for storeId: String) -> String? {
        storeFrontValues.first(where: { $0.value == storeId })?.key
    }

    public static func accountPath(for email: String) -> URL {
        let emailLower = email.lowercased()
        let hash = emailLower.md5
        let accountDir = homePath.appendingPathComponent(hash)
        try? FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        return accountDir.appendingPathComponent("account.json")
    }

    public static func saveLoginAccount(_ account: Account, for email: String) {
        let fileURL = accountPath(for: email)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try! encoder.encode(account)
        try! data.write(to: fileURL)
    }

    public static func withAccount<T>(email: String, _ body: (inout Account) async throws -> T) async throws -> T {
        var account: Account = try {
            let fileURL = accountPath(for: email)
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Account.self, from: data)
        }()
        defer { saveLoginAccount(account, for: email) }
        return try await body(&account)
    }
}

private let kCountryCodes = [
    "AE": "143481",
    "AG": "143540",
    "AI": "143538",
    "AL": "143575",
    "AM": "143524",
    "AO": "143564",
    "AR": "143505",
    "AT": "143445",
    "AU": "143460",
    "AZ": "143568",
    "BB": "143541",
    "BD": "143490",
    "BE": "143446",
    "BG": "143526",
    "BH": "143559",
    "BM": "143542",
    "BN": "143560",
    "BO": "143556",
    "BR": "143503",
    "BS": "143539",
    "BW": "143525",
    "BY": "143565",
    "BZ": "143555",
    "CA": "143455",
    "CH": "143459",
    "CI": "143527",
    "CL": "143483",
    "CN": "143465",
    "CO": "143501",
    "CR": "143495",
    "CY": "143557",
    "CZ": "143489",
    "DE": "143443",
    "DK": "143458",
    "DM": "143545",
    "DO": "143508",
    "DZ": "143563",
    "EC": "143509",
    "EE": "143518",
    "EG": "143516",
    "ES": "143454",
    "FI": "143447",
    "FR": "143442",
    "GB": "143444",
    "GD": "143546",
    "GE": "143615",
    "GH": "143573",
    "GR": "143448",
    "GT": "143504",
    "GY": "143553",
    "HK": "143463",
    "HN": "143510",
    "HR": "143494",
    "HU": "143482",
    "ID": "143476",
    "IE": "143449",
    "IL": "143491",
    "IN": "143467",
    "IS": "143558",
    "IT": "143450",
    "IQ": "143617",
    "JM": "143511",
    "JO": "143528",
    "JP": "143462",
    "KE": "143529",
    "KN": "143548",
    "KR": "143466",
    "KW": "143493",
    "KY": "143544",
    "KZ": "143517",
    "LB": "143497",
    "LC": "143549",
    "LI": "143522",
    "LK": "143486",
    "LT": "143520",
    "LU": "143451",
    "LV": "143519",
    "MD": "143523",
    "MG": "143531",
    "MK": "143530",
    "ML": "143532",
    "MN": "143592",
    "MO": "143515",
    "MS": "143547",
    "MT": "143521",
    "MU": "143533",
    "MV": "143488",
    "MX": "143468",
    "MY": "143473",
    "NE": "143534",
    "NG": "143561",
    "NI": "143512",
    "NL": "143452",
    "NO": "143457",
    "NP": "143484",
    "NZ": "143461",
    "OM": "143562",
    "PA": "143485",
    "PE": "143507",
    "PH": "143474",
    "PK": "143477",
    "PL": "143478",
    "PT": "143453",
    "PY": "143513",
    "QA": "143498",
    "RO": "143487",
    "RS": "143500",
    "RU": "143469",
    "SA": "143479",
    "SE": "143456",
    "SG": "143464",
    "SI": "143499",
    "SK": "143496",
    "SN": "143535",
    "SR": "143554",
    "SV": "143506",
    "TC": "143552",
    "TH": "143475",
    "TN": "143536",
    "TR": "143480",
    "TT": "143551",
    "TW": "143470",
    "TZ": "143572",
    "UA": "143492",
    "UG": "143537",
    "US": "143441",
    "UY": "143514",
    "UZ": "143566",
    "VC": "143550",
    "VE": "143502",
    "VG": "143543",
    "VN": "143471",
    "YE": "143571",
    "ZA": "143472",
]
