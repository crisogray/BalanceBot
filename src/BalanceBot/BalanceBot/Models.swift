//
//  Models.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import Foundation
import CloudKit
import SwiftUI

struct Account: Codable, Equatable {
    var id: String
    var portfolioId: String
    var connectedExchanges: [String : [String : String]]
    var excludedBalances: [String]
}

struct Portfolio: Codable, Equatable {
    var id: String
    var strategy: String
    var targetAllocation: [String : Float]
    var balances: [String : Float]
    var isLive: Int
}

struct UserSettings: Codable, Equatable {
    var account: Account
    var portfolio: Portfolio
    
}

struct Balance: Codable, Equatable {
    var ticker: String
    var value: Float
    var usdValue: Float
    var exchange: String
}

extension Balance {
    struct ExchangeBalance: Codable, Equatable {
        var ticker: String
        var value: Float
        var exchange: String
    }
}

extension Balance.ExchangeBalance {
    func convertToUSD(prices: [String : Float]) -> Balance {
        let rate = prices[ticker] ?? 0
        return Balance(ticker: ticker, value: value, usdValue: value * rate, exchange: exchange)
    }
}

enum Exchange: String, Hashable, Codable, CaseIterable {
    
    static var sortedAllCases: [Exchange] {
        allCases.sorted { $0.rawValue < $1.rawValue }
    }
    
    case bitfinex = "Bitfinex", binance = "Binance", ftx = "FTX", kraken = "Kraken", coinbase = "Coinbase"
    
    var regexPattern: String {
        switch self {
        case .bitfinex: return "-key:(\\w+)-secret:(\\w+)\\Z"
        default: return ""
        }
    }
    
    func parseAPIKeyQRString(_ qr: String) -> Result<(String, String), Error> {
        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [])
            guard let match = regex.firstMatch(in: qr, options: [], range: NSRange(location: 0, length: qr.count)),
                  let keyRange = Range(match.range(at: 1), in: qr),
                  let secretRange = Range(match.range(at: 2), in: qr) else {
                      throw RegexError.regexFailed
            }
            return .success((String(qr[keyRange]), String(qr[secretRange])))
        } catch {
            return .failure(error)
        }
        
    }
    
}

enum RegexError: Error {
    case regexFailed
}
