//
//  Models.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import CloudKit

struct Account: Codable, Equatable {
    var id: String
    var portfolioId: String
    var connectedExchanges: [String : [String : String]]
    var excludedBalances: [String : [String]]
}

struct Portfolio: Codable, Equatable {
    var id: String
    var strategy: String
    var targetAllocation: [String : Double]
    var balances: [String : Double]
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

typealias BalanceList = [Balance]

extension BalanceList {
    
    var total: Double { map { $0.usdValue }.reduce(0, +) }
    
    func grouped<T: Hashable>(by keyPath: KeyPath<Balance, T>) -> [T : BalanceList] {
        .init(grouping: self, by: { $0[keyPath: keyPath] })
    }
    
    func sorted<T: Comparable>(_ keyPath: KeyPath<Balance, T>) -> BalanceList {
        sorted { $0[keyPath: keyPath] > $1[keyPath: keyPath] }
    }
    
}

typealias GroupedBalances<T: Hashable> = [T : BalanceList]

extension GroupedBalances where Value == BalanceList {
    
    var sortedKeys: [Key] {
        Array(keys).sorted { one, two in
            self[one]!.total > self[two]!.total
        }
    }
    
}

extension Array where Element == Balance.ExchangeBalance {
    func convertToBalances(_ prices: [Balance.Price]) -> [Balance] {
        return compactMap { exchangeBalance in
            if exchangeBalance.ticker == "USD" {
                return Balance(exchangeBalance)
            } else if let price = prices.first(
                where: { $0.ticker == exchangeBalance.ticker }) {
                return Balance(exchangeBalance, price: price.price)
            }
            return nil
        }
    }
    
}

enum AppError: Error {
    case noRegexMatches, invalidRequest
}

