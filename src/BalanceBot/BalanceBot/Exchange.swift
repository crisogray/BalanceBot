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
        case .ftx, .kraken: return true
        default: return false
        }
    }
    
    func createHeaders(path: String, body: [String : String], key: String, secret: String, nonce: String) -> [String : String] {
        //let signature = signature(for: self, path: path, body: body, secret: secret, nonce: nonce)
        switch self {
        case .bitfinex:
            let signature = Exchange.signHMAC("/api/\(path)\(nonce)\(body.jsonString)",
                                     hmac: HMAC<SHA384>.self, key: key, secret: secret)
            return ["Content-Type": "application/json", "bfx-nonce": nonce,
                    "bfx-apikey": key, "bfx-signature": signature]
        case .kraken:
            let path = "/0/\(path)"
            let encodedParams = body.queryString
            let decodedSecret = Data(base64Encoded: secret)!
            let digest = (nonce + encodedParams).data(using: .utf8)!
            let encodedPath = path.data(using: .utf8)!
            let message = SHA256.hash(data: digest)
            let messagePath = encodedPath + message
            let signature = Data(HMAC<SHA512>.authenticationCode(for: messagePath, using: SymmetricKey(data: decodedSecret))) //HMAC.sign(data: messagePath, algorithm: HMAC.Algorithm.sha512, key: decodedSecret)
            //let signature = Exchange.signHMAC(string, hmac: HMAC<SHA512>.self, key: key, secret: secret)
            print(signature.base64EncodedString())
            print(key)
            return ["API-Key" : key, "API-Sign" : signature.base64EncodedString()]
            default: return [:]
        }
        
    }
    
    static func signHMAC<H>(_ string: String, hmac: HMAC<H>.Type, key: String, secret: String) -> String {
        let key = SymmetricKey(data: secret.data(using: .utf8)!)
        let signature = hmac.authenticationCode(for: string.data(using: .utf8)!, using: key)
        return Data(signature).map { String(format: "%02hhx", $0) }.joined()
    }
    
}


// MARK: API Response

// Decomposition scheme for request type

extension Exchange {
    
    var priceTickerRegexPattern: String {
        switch self {
        case .bitfinex: return "^t(.+)USD\\Z"
        case .kraken: return "^X(.+?)Z?USD\\Z"
        default: return ""
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
            guard let match = regex.firstMatch(in: ticker, options: [], range: NSRange(location: 0, length: ticker.count)),
                  let currencyRange = Range(match.range(at: 1), in: ticker) else {
                      throw RegexError.noKeyPairFound
            }
            return String(ticker[currencyRange])
        } catch { return ticker }
    }
    
}
