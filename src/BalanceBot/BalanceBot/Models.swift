//
//  Models.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import CloudKit
import Combine
import SwiftUI

struct Account: Codable, Equatable {
    var id: String
    var portfolioId: String
    var connectedExchanges: [String : [String : String]]
    var excludedBalances: [String : [String]]
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

struct Balance: Equatable {
    var ticker: String
    var balance: Double
    var price: Double
    var usdValue: Double
    var exchange: Exchange
    
    init(_ exchangeBalance: ExchangeBalance, price: Double = 1) {
        ticker = exchangeBalance.exchange.renames[exchangeBalance.ticker] ?? exchangeBalance.ticker
        balance = exchangeBalance.balance
        self.price = price
        usdValue = exchangeBalance.balance * price
        exchange = exchangeBalance.exchange
    }
    
}

struct BalanceList: Equatable {
    
    var total: Double
    var balances: [Balance]
    
    init(_ balances: [Balance]) {
        self.balances = balances
        total = balances.map { $0.usdValue }.reduce(0, +)
    }
    
    func groupedBy(_ keyPath: KeyPath<Balance, String>) -> [String : BalanceList] {
        [String : [Balance]]
            .init(grouping: balances, by: { $0[keyPath: keyPath] })
            .mapValues { BalanceList($0) }
    }
    
}

extension Array where Element == Balance.ExchangeBalance {
    func convertToBalances(_ prices: [Balance.Price]) -> [Balance] {
        return compactMap { exchangeBalance in
            if exchangeBalance.ticker == "USD" {
                return Balance(exchangeBalance)
            } else if let price = prices.first(where: { price in
                price.ticker == exchangeBalance.ticker
            }) {
                return Balance(exchangeBalance, price: price.price)
            }
            return nil
        }
    }
    
}

enum AppError: Error {
    case noRegexMatches, invalidRequest
}

