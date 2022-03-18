//
//  ExchangesInteractor.swift
//  BalanceBot
//
//  Created by Ben Gray on 04/02/2022.
//

import Foundation
import Combine
import SwiftUI

protocol ExchangesInteractor {
    func fetchExchangeData(for account: Account)
    func calculateRebalance(for userSettings: UserSettings, with exchangeData: ExchangeData,
                            transactions: Binding<[String]?>)
}

struct RealExchangesInteractor: ExchangesInteractor {
    
    var appState: Store<AppState>
    var exchangeRepository: ExchangeRepository
    
    // MARK: Request Exchange Data
    
    func fetchExchangeData(for account: Account) {
        let cancelBag = CancelBag()
        appState[\.exchangeData].setIsLoading(cancelBag: cancelBag)
        requestExchangeData(for: account)
            .sink { completion in
                guard case .failure(let error) = completion else { return }
                appState[\.exchangeData] = .failed(error)
            } receiveValue: { balances, tickers in
                appState[\.exchangeData] = .loaded(ExchangeData(balances: balances, tickers: tickers))
            }.store(in: cancelBag)

    }
    
    private func requestExchangeData(for account: Account) -> AnyPublisher<(BalanceList, [Ticker]), Error> {
        Publishers.Zip(requestBalances(for: account), requestTickers(for: account))
            .flatMap { balanceCollection, tickerCollection -> AnyPublisher<(BalanceList, [Ticker]), Error> in
                let balances = balanceCollection.flatMap { $0 }
                var tickers = tickerCollection.flatMap { $0 }
                    .filter { allowedTickers.contains($0.ticker) }
                tickers.addUnique(contentsOf: balances.map { Ticker([$0.ticker, $0.exchange])! } )
                return Just((balances, tickers)).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // MARK: Request Balances
    
    private func requestBalances(for account: Account) -> AnyPublisher<[BalanceList], Error> {
        Publishers.ZipMany<BalanceList, Error>(
            account.connectedExchanges.compactMap { exchangeName, keys in
                guard let exchange = Exchange(rawValue: exchangeName),
                      let key = keys["key"], let secret = keys["secret"] else {
                    return nil
                }
                return exchangeRepository
                    .getBalances(on: exchange, with: key, and: secret)
                    .eraseToAnyPublisher()
            }
        ).eraseToAnyPublisher()
    }
    
    // MARK: Request Tickers
    
    private func requestTickers(for account: Account) -> AnyPublisher<[[Ticker]], Error> {
        Publishers.ZipMany<[Ticker], Error>(
            account.connectedExchanges.compactMap { exchangeName, keys in
                guard let exchange = Exchange(rawValue: exchangeName) else { return nil }
                return exchangeRepository.getTickers(on: exchange)
            }
        ).eraseToAnyPublisher()
    }
    
    // MARK: Calculate Rebalance
    
    func calculateRebalance(for userSettings: UserSettings, with exchangeData: ExchangeData,
                            transactions: Binding<[String]?>) {
        DispatchQueue.global().async {
            let total = exchangeData.balances.total(\.usdValue)
            let targetAllocation = userSettings.portfolio.targetAllocation
            let currentAllocation = currentAllocation(exchangeData.balances, userSettings.portfolio)
            
            let targetTickers = Set(targetAllocation.keys)
            let currentTickers = Set(currentAllocation.keys)
            
            var deltas: [String : Double] = [:]
            
            var ignoredDelta: Double = 0
            for ticker in currentTickers.union(targetTickers) {
                let delta = (targetAllocation[ticker] ?? 0) -
                            (currentAllocation[ticker] ?? 0)
                if delta < 1 && delta > -1 {
                    ignoredDelta += abs(delta)
                } else if let group = userSettings.portfolio.assetGroups[ticker] {
                    let balances = exchangeData.balances
                        .filter { group.contains($0.ticker) }
                        .grouped(by: \.ticker)
                    deltasForGroup(group, balances: balances, delta: total * delta / 100)
                        .forEach { deltas[$0] = $1 }
                } else if ticker != "USD" {
                    deltas[ticker] = total * delta / 100
                }
            }
            deltas = deltas.mapValues {
                let share = total * ignoredDelta / Double(100 * deltas.count)
                return $0 < 0 ? min($0 + share, 0) : max($0 - share, 0)
            }
            
            // MARK: Part 2: Liquidity Matching
            
            let t = (1...20).map { _ -> [String] in
                deltaTransactions(deltas,
                                  balances: exchangeData.balances.grouped(by: \.ticker),
                                  tickers: exchangeData.tickers)
            }.sorted(by: { $0.count < $1.count }).first
            
            DispatchQueue.main.async {
                transactions.wrappedValue = t
            }
        }
        
    }
    
    private func deltaTransactions(_ deltas: [String : Double],
                                   balances: [String : BalanceList],
                                   tickers: [Ticker]) -> [String] {
        
        var sellTransactions: [String] = []
        var buyTransactions: [String] = []

        // Sells
        let sells = deltas.filter { $1 < 0 }
        let buys = deltas.filter { $1 > 0 }
        
        var sellLiq: [Exchange : [(String, Double)]] = [:]
        var buyLiq: [Set<Exchange> : [(String, Double)]] = [:]
        
        for (ticker, delta) in sells {
            let balances = balances[ticker]!
            for balance in balances {
                if let _ = sellLiq[balance.exchange] {
                    sellLiq[balance.exchange]!.append((ticker, max(-balance.usdValue, delta)))
                } else {
                    sellLiq[balance.exchange] = [(ticker, max(-balance.usdValue, delta))]
                }
            }
        }
        
        for (ticker, delta) in buys {
            let exchanges = Set(tickers.compactMap { t -> Exchange? in
                return t.ticker == ticker ? t.exchange : nil
            })
            if let _ = buyLiq[exchanges] {
                buyLiq[exchanges]!.append((ticker, delta))
            } else {
                buyLiq[exchanges] = [(ticker, delta)]
            }
        }
        
        // Match Liquidity
        
        var postSellLiq: [Exchange : Double] = [:]
        
        if let currentUSD = balances["USD"] {
            for balance in currentUSD {
                postSellLiq[balance.exchange] = balance.usdValue
            }
        }
        
        for (ticker, delta) in sells {
            let exchangesWithSellLiquidity = sellLiq
                .filter { _, ts in ts.contains(where: { $0.0 == ticker }) }
                .mapValues { ts in
                    ts.compactMap { (k, v) -> Double? in
                        return k == ticker ? v : nil
                    }.first!
                }
                .sorted(by: { abs($0.1) > abs($1.1) })
            var d = delta, i = 0
            while d < 0 {
                let value = min(d, exchangesWithSellLiquidity[i].value)
                let exchange = exchangesWithSellLiquidity[i].key
                if value == d {
                    i += 1
                }
                d -= value
                sellTransactions.append("Sell \(abs(value).usdFormat) of \(ticker) on \(exchange.rawValue)")
                if let currentBalance = postSellLiq[exchange] {
                    postSellLiq[exchange] = currentBalance + abs(value)
                } else {
                    postSellLiq[exchange] = abs(value)
                }
                /*if let index = sellLiq[exchange]?.firstIndex(where: { $0.0 == ticker }) {
                    let v: Double = sellLiq[exchange]![index].1
                    if v == value {
                        sellLiq[exchange]!.remove(at: index)
                    } else {
                        sellLiq[exchange]![index].1 = v - value
                    }
                }
                i += 1*/
            }
        }
        
        var sortedLiq = postSellLiq.sorted { $0.value > $1.value }
        var i = 0, j = 0
        for (exchange, liquidity) in sortedLiq {
            var liquidity = liquidity
            let keys = buyLiq.keys.filter { $0.contains(exchange) }.sorted { $0.count < $1.count }
            let tempBuyLiq = buyLiq
            while liquidity > 0, i < keys.count {
                let key = keys[i]
                while liquidity > 0, j < tempBuyLiq[key]!.count {
                    let ticker = tempBuyLiq[key]![j]
                    let value = min(ticker.1, liquidity)
                    if let index = buyLiq[key]?.firstIndex(where: { $0.1 == value}) {
                        if tempBuyLiq[key]![j].1 == value {
                            buyLiq[key]!.remove(at: index)
                            j += 1
                        } else {
                            buyLiq[key]![index].1 = buyLiq[key]![index].1 - value
                        }
                    }
                    postSellLiq[exchange] = postSellLiq[exchange]! - value
                    liquidity -= value
                    buyTransactions.append("Buy \(value.usdFormat) of \(ticker.0) on \(exchange.rawValue)")
                }
                if liquidity > 0 {
                    i += 1
                    j = 0
                }
            }
        }
        
        var exchangeTransfers: [String : Double] = [:]
        sortedLiq = postSellLiq.sorted { $0.value > $1.value }
        var outliers = buyLiq.filter { !$1.isEmpty }
        if !outliers.isEmpty {
            var i = 0, j = 0
            for (exchange, liquidity) in sortedLiq {
                var liquidity = liquidity
                let outlierKeys = Array(outliers.keys)
                while liquidity > 0, i < outlierKeys.count {
                    let exchange2 = outlierKeys[i].first!
                    let needs = outliers[outlierKeys[i]]!
                    while liquidity > 0, j < needs.count {
                        let need = needs[j]
                        let value = min(liquidity, need.1)
                        if exchange != exchange2 {
                            let transferKey = "\(exchange.rawValue):\(exchange2.rawValue)"
                            if let currentValue = exchangeTransfers[transferKey] {
                                exchangeTransfers[transferKey] = currentValue + value
                            } else {
                                exchangeTransfers[transferKey] = value
                            }
                        }
                        buyTransactions.insert("Buy \(value.usdFormat) of \(need.0) on \(exchange2.rawValue)", at: 0)
                        outliers[outlierKeys[i]]![j].1 = outliers[outlierKeys[i]]![j].1 - value
                        liquidity -= value
                        if need.1 == value {
                            j += 1
                        }
                    }
                    if liquidity > 0 {
                        i += 1
                        j = 0
                    }
                }
            }
        }
        
        let transfers = exchangeTransfers.map { key, value -> String in
            let exchanges = key.split(separator: ":")
            return "Transfer \(value.usdFormat) from \(exchanges[0]) to \(exchanges[1])"
        }
        
        return sellTransactions + transfers + buyTransactions
    }
    
    private func deltasForGroup(_ group: [String],
                                balances: [String : BalanceList],
                                delta: Double) -> [String : Double] {
        let total = balances.map { $1.total(\.usdValue) }.total
        let target = total + delta
        let equilibrium = target / Double(group.count)
        let deltaBalances = balances.filter { _, balance in
            let total = balance.total(\.usdValue)
            return delta > 0 ? (total < equilibrium) : (total > equilibrium)
        }
        return deltaBalances.mapValues { _ in delta / Double(deltaBalances.count) }
    }
    
    private func currentAllocation(_ balances: BalanceList, _ portfolio: Portfolio) -> [String : Double] {
        let total = balances.total(\.usdValue)
        var allocation: [String : Double] = balances.grouped(by: \.ticker).mapValues {
            100.0 * $0.total(\.usdValue) / total
        }
        let activeGroups = portfolio.assetGroups.filter { key, _ in
            portfolio.targetAllocation[key] != nil
        }
        for (name, group) in activeGroups {
            allocation[name] = group.compactMap {
                allocation.removeValue(forKey: $0)
            }.total
        }
        portfolio.targetAllocation.keys.filter { allocation[$0] == nil }.forEach {
            allocation[$0] = 0.0
        }
        return allocation
    }
    
}

