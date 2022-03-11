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
    var rebalanceTrigger: String
    var targetAllocation: [String : Double]
    var balances: [String : Double]
    var assetGroups: [String : [String]]
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

struct ExchangeData: Equatable {
    var balances: BalanceList
    var tickers: [Ticker]
}

typealias BalanceList = [Balance]

extension BalanceList {
    var usdTotal: Double { map { $0.usdValue }.total }
}

extension Array where Element: Equatable {
    
    func sorted<T: Comparable>(_ keyPath: KeyPath<Element, T>, ascending: Bool = false) -> [Element] {
        sorted { ($0[keyPath: keyPath] > $1[keyPath: keyPath]) != ascending }
    }
    
    func grouped<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [T : [Element]] {
        .init(grouping: self, by: { $0[keyPath: keyPath] })
    }
    
    func notInReplacements<T: Hashable>(_ replacements: [T : [Element]]) -> [Element] {
        let values = replacements.values.flatMap { $0 }
        return filter { !values.contains($0) }
    }
    
    mutating func addUnique(contentsOf array: [Element]) {
        array.forEach { element in
            if !contains(element) {
                append(element)
            }
        }
    }
    
}

extension Sequence where Element: Hashable {
    
    var unique: [Element] {
        Array(Set(self))
    }
    
}

extension Dictionary where Value == BalanceList {
    var sortedKeys: [Key] { keys.sorted { self[$0]!.usdTotal > self[$1]!.usdTotal } }
}

extension Sequence where Element == String {
    func withReplacements(_ replacements: [String : [String]]) -> [Element] {
        var tickers = Array(self.sorted())
        tickers.insert(contentsOf: replacements.keys, at: 0)
        return tickers.notInReplacements(replacements)
    }
}

enum AppError: Error {
    case noRegexMatches, invalidRequest
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

