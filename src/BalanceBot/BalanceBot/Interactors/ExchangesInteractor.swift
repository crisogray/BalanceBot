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
                            _ total: Binding<Int>, _ progress: Binding<Int>, transactions: Binding<[String]?>)
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
    
    func calculateRebalance(for userSettings: UserSettings, with exchangeData: ExchangeData,
                            _ iterations: Binding<Int>, _ progress: Binding<Int>, transactions: Binding<[String]?>) {
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
            
        let count = deltas.count * 300
        iterations.wrappedValue = count
        progress.wrappedValue = 0
        
        DispatchQueue.global().async {
            let t = (1...count).map { i -> [String] in
                DispatchQueue.main.async {
                    progress.wrappedValue = i
                }
                return transactionSolution(deltas, exchangeData: exchangeData)
            }.sorted(by: { $0.count < $1.count }).first
            
            DispatchQueue.main.async {
                transactions.wrappedValue = t
            }
        }
        
    }
    
    private func transactionSolution(_ deltas: [String : Double],
                                     exchangeData: ExchangeData) -> [String] {
        
        let balances = exchangeData.balances.grouped(by: \.ticker)
        let tickers = exchangeData.tickers
        
        var sellTransactions: [String] = []
        var buyTransactions: [String : Double] = [:]

        let sells = deltas.filter { $1 < 0 }
        
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
        
        for (ticker, delta) in deltas.filter({ $1 > 0 }) {
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
                }.shuffled()
                //.sorted(by: { abs($0.1) > abs($1.1) })
            var d = delta, i = 0
            while d < 0, i < exchangesWithSellLiquidity.count {
                let value = max(d, exchangesWithSellLiquidity[i].value)
                let exchange = exchangesWithSellLiquidity[i].key
                if value == exchangesWithSellLiquidity[i].value {
                    i += 1
                }
                d -= value
                sellTransactions.append("Sell \(abs(value).usdFormat) of \(ticker) on \(exchange.rawValue)")
                if let currentBalance = postSellLiq[exchange] {
                    postSellLiq[exchange] = currentBalance + abs(value)
                } else {
                    postSellLiq[exchange] = abs(value)
                }
            }
        }
        
        var sortedLiq = postSellLiq.shuffled()//.sorted { $0.value > $1.value }
        var i = 0, j = 0
        for (exchange, liquidity) in sortedLiq {
            var liquidity = liquidity
            let keys = buyLiq.keys.filter { $0.contains(exchange) }.shuffled()//.sorted { $0.count < $1.count }
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
                    let buyKey = "\(ticker.0):\(exchange.rawValue)"
                    buyTransactions[buyKey] = value + (buyTransactions[buyKey] ?? 0)
                }
                if liquidity > 0 {
                    i += 1
                    j = 0
                }
            }
        }
        
        var exchangeTransfers: [String : Double] = [:]
        sortedLiq = postSellLiq.shuffled()//.sorted { $0.value > $1.value }
        var outliers = buyLiq.filter { !$1.isEmpty }
        if !outliers.isEmpty {
            var i = 0, j = 0
            for (exchange, liquidity) in sortedLiq {
                var liquidity = liquidity
                let outlierKeys = Array(outliers.keys)
                while liquidity > 0, i < outlierKeys.count {
                    let exchange2 = outlierKeys[i].randomElement()!//.first!
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
                        let buyKey = "\(need.0):\(exchange2.rawValue)"
                        buyTransactions[buyKey] = value + (buyTransactions[buyKey] ?? 0)
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
        
        let buys = buyTransactions.map { key, value -> String in
            let k = key.split(separator: ":")
            return "Buy \(value.usdFormat) of \(k[0]) on \(k[1])"
        }
        
        return sellTransactions + transfers + buys
    }
    
}

