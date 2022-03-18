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

struct Portfolio: Equatable {
    var id: String
    var rebalanceTrigger: RebalanceTrigger
    var targetAllocation: [String : Double]
    var balances: [String : Double]
    var assetGroups: [String : [String]]
    var isLive: Int
}

struct UserSettings: Equatable {
    var account: Account
    var portfolio: Portfolio
    var hasNotifications: Bool
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
    
    func total(_ path: KeyPath<Balance, Double>) -> Double {
        return map { $0[keyPath: path] }.total
    }
    
}


enum RebalanceTrigger: Hashable {
    
    enum CalendarSchedule: String, CaseIterable {
        case weekly, monthly, quarterly, sixMonthly = "six-monthly", yearly
        
        var displayString: String {
            rawValue.capitalized
        }
        
    }
    
    case calendar(CalendarSchedule)
    case threshold(Int)
    
    var storedString: String {
        switch self {
        case .calendar(let schedule): return "calendar:\(schedule.rawValue)"
        case .threshold(let int): return "threshold:\(int)"
        }
    }
    
}

extension RebalanceTrigger {
    init(_ string: String) {
        let components = string.lowercased().components(separatedBy: ":")
        self = components[0] == "calendar" ?
            .calendar(.init(rawValue: components[1])!) :
            .threshold(Int(components[1])!)
    }
    
    func isSameType(as other: RebalanceTrigger) -> Bool {
        switch (self, other) {
        case (.calendar, .calendar),
            (.threshold, .threshold): return true
        default: return false
        }
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
            } else if let price = prices.first(where: {
                $0.ticker == exchangeBalance.ticker
            }) { return Balance(exchangeBalance, price: price.price) }
            print(exchangeBalance.ticker)
            return nil
        }
    }
    
}

