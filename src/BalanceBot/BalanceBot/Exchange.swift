//
//  Exchange.swift
//  BalanceBot
//
//  Created by Ben Gray on 15/02/2022.
//

import Foundation
import Combine


// MARK: Definition

enum Exchange: String, CaseIterable {
    
    case bitfinex = "Bitfinex",
         binance = "Binance",
         ftx = "FTX",
         kraken = "Kraken",
         coinbase = "Coinbase"
    
    static var sortedAllCases: [Exchange] {
        allCases.sorted { $0.rawValue < $1.rawValue }
    }
    
}

// MARK: QR Reading

extension Exchange {
        
    var qrRegexPattern: String {
        switch self {
        case .bitfinex: return "-key:(.+)-secret:(.+)\\Z"
        case .kraken: return "key=(.+)&secret=(.+)\\Z"
        default: return ""
        }
    }
    
    func parseAPIKeyQRString(_ qr: String) -> Result<(String, String), Error> {
        do {
            let regex = try NSRegularExpression(pattern: qrRegexPattern, options: [])
            guard let match = regex.firstMatch(in: qr, options: [], range: NSRange(location: 0, length: qr.count)),
                  let keyRange = Range(match.range(at: 1), in: qr),
                  let secretRange = Range(match.range(at: 2), in: qr) else {
                      throw RegexError.noKeyPairFound
            }
            return .success((String(qr[keyRange]), String(qr[secretRange])))
        } catch { return .failure(error) }
    }
    
}

// MARK: API Request

import CryptoKit

extension Exchange {
    
    var publicBaseURL: String {
        switch self {
        case .bitfinex: return "https://api-pub.bitfinex.com/v2/"
        case .kraken: return "https://api.kraken.com/0/"
        case .coinbase: return "https://api.coinbase.com/v2/"
        case .ftx: return "https://ftx.com/api/"
        default: return ""
        }
    }
    
    var authenticatedBaseUrl: String {
        switch self {
        case .bitfinex: return "https://api.bitfinex.com/"
        default: return publicBaseURL
        }
    }
    
    var singlePriceRequest: Bool {
        switch self {
        case .ftx, .kraken, .coinbase: return true
        default: return false
        }
    }
    
    var completeBalanceRequest: Bool {
        switch self {
        case .ftx: return true
        default: return false
        }
    }
    
    var canQR: Bool {
        switch self {
        case .bitfinex, .kraken: return true
        default: return false
        }
    }
    
    func createHeaders(path: String, body: [String : String], key: String, secret: String, nonce: String, method: String) -> [String : String] {
        switch self {
        case .bitfinex:
            let signature = Exchange.signHMAC("/api/\(path)\(nonce)\(body.jsonString)",
                                              hmac: HMAC<SHA384>.self, secret: secret)
            return ["Content-Type": "application/json", "bfx-nonce": nonce,
                    "bfx-apikey": key, "bfx-signature": signature]
        case .kraken:
            let secretKey = SymmetricKey(data: Data(base64Encoded: secret)!)
            let digest = (nonce + body.queryString).data(using: .utf8)!
            let messagePath = "/0/\(path)".data(using: .utf8)! + SHA256.hash(data: digest)
            let signature = Data(HMAC<SHA512>.authenticationCode(for: messagePath, using: secretKey))
            return ["API-Key" : key, "API-Sign" : signature.base64EncodedString()]
        case .coinbase:
            let message = nonce + method + "/v2/\(path)" + (body.isEmpty ? "" : body.jsonString)
            let signature = Exchange.signHMAC(message, hmac: HMAC<SHA256>.self, secret: secret)
            return ["Accept" : "application/json", "CB-ACCESS-KEY" : key,
                    "CB-ACCESS-TIMESTAMP" : nonce, "CB-ACCESS-SIGN" : signature]
        case .ftx:
            let nonce = String(Int(nonce)! * 1000)
            let message = nonce + method + "/api/\(path)"
            let signature = Exchange.signHMAC(message, hmac: HMAC<SHA256>.self, secret: secret)
            return ["FTX-KEY" : key, "FTX-TS" : nonce, "FTX-SIGN" : signature.lowercased()]
        default: return [:]
        }
        
    }
    
    static func signHMAC<H>(_ string: String, hmac: HMAC<H>.Type, secret: String) -> String {
        let key = SymmetricKey(data: secret.data(using: .utf8)!)
        let signature = hmac.authenticationCode(for: string.data(using: .utf8)!, using: key)
        return Data(signature).map { String(format: "%02hhx", $0) }.joined()
    }
    
}

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return self.map { String(format: format, $0) }.joined()
    }
}

// MARK: API Response

// Decomposition scheme for request type

extension Exchange {
    
    var priceTickerRegexPattern: String {
        switch self {
        case .bitfinex: return "^t(.+)USD\\Z"
        case .kraken: return "^X(.+?)Z?USD\\Z"
        default: return "^(.+)\\Z"
        }
    }
    
    var balanceTickerRegexPattern: String {
        switch self {
        case .kraken: return "^[XZ]?(.+)$"
        default: return priceTickerRegexPattern
        }
    }
    
    var renames: [String : String] {
        switch self {
        case .kraken: return ["XBT" : "BTC"]
        default: return [:]
        }
    }
    
    func currency(from ticker: String, _ balance: Bool = false) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: balance ? balanceTickerRegexPattern : priceTickerRegexPattern, options: [])
            guard let match = regex.firstMatch(in: ticker, options: [],range: NSRange(location: 0, length: ticker.count)),
                  let currencyRange = Range(match.range(at: 1), in: ticker) else {
                      throw RegexError.noKeyPairFound
            }
            return String(ticker[currencyRange])
        } catch { return ticker }
    }
    
}
