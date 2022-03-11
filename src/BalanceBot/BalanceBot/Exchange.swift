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
                      throw AppError.noRegexMatches
                  }
            return .success((String(qr[keyRange]), String(qr[secretRange])))
        } catch {
            return .failure(error)
        }
    }
    
}

// MARK: API Request

extension Exchange {
    
    var publicBaseURL: String {
        switch self {
        case .bitfinex: return "https://api-pub.bitfinex.com/v2/"
        case .kraken: return "https://api.kraken.com/0/"
        case .coinbase: return "https://api.coinbase.com/v2/"
        case .ftx: return "https://ftx.com/api/"
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
    
    var balancesInOneStep: Bool {
        switch self {
        case .ftx: return true
        default: return false
        }
    }
    
    var canQR: Bool {
        qrRegexPattern != ""
    }
    
}

// MARK: API Response

extension Exchange {
    
    var priceTickerRegexPattern: String {
        switch self {
        case .bitfinex: return "^t(.+?)(USD)?(BTC)?(ETH)?$"
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
                      throw AppError.noRegexMatches
            }
            return String(ticker[currencyRange])
        } catch { return ticker }
    }
    
}
