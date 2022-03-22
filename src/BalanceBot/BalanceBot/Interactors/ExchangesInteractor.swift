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
    
    private func deltasForGroup(_ group: [String], balances: [String : BalanceList],
                                delta: Double) -> [String : Double] {
        let total = balances.map { $1.total(\.usdValue) }.total
        let equilibrium = (total + delta) / Double(group.count)
        return balances.compactMapValues { balance -> Double? in
            let total = balance.total(\.usdValue)
            let include = (delta > 0) == (total < equilibrium)
            return include ? delta * abs(total - equilibrium) / abs(delta) : nil
        }
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
        
        print(deltas)
                    
        let count = deltas.count * 400
        iterations.wrappedValue = count
        progress.wrappedValue = 0
        
        DispatchQueue.global().async {
            let t = (1...count).map { i -> [String] in
                DispatchQueue.main.async { progress.wrappedValue = i }
                return transactionSolution(deltas, exchangeData: exchangeData)
            }.sorted(by: { $0.count < $1.count }).first
            DispatchQueue.main.async { transactions.wrappedValue = t }
        }
        
    }
        
    // MARK: Part 2: Liquidity Matching
    
    private func transactionSolution(_ deltas: [String : Double],
                                     exchangeData: ExchangeData) -> [String] {
        
        let balances = exchangeData.balances.grouped(by: \.ticker)
        let tickers = exchangeData.tickers
        
        var sellTransactions: [String] = []
        var buyTransactions: [String : Double] = [:]
        
        var buyLiq: [Set<Exchange> : [(String, Double)]] = [:]
        
        for (ticker, delta) in deltas.filter({ $1 > 0 }) {
            let exchanges = Set(tickers.compactMap { $0.ticker == ticker ? $0.exchange : nil })
            buyLiq[exchanges] = (buyLiq[exchanges] ?? []) + [(ticker, delta)]
        }
        
        var postSellLiq: [Exchange : Double] = [:]
        
        for balance in balances["USD"] ?? [] {
            postSellLiq[balance.exchange] = balance.usdValue
        }
                
        for (ticker, delta) in deltas.filter({ $1 < 0 }) {
            let exchangesWithSellLiquidity = (balances[ticker] ?? []).map {
                ($0.exchange, max(-$0.usdValue, delta))
            }.shuffled()
            var d = delta, i = 0
            while d < 0, i < exchangesWithSellLiquidity.count {
                let (exchange, v) = exchangesWithSellLiquidity[i]
                let value = max(d, v)
                sellTransactions.append("Sell \(abs(value).usdFormat) of \(ticker) on \(exchange.rawValue)")
                postSellLiq[exchange] = (postSellLiq[exchange] ?? 0.0) + abs(value)
                d -= value
                i += value == v ? 1 : 0
            }
        }
        
        liquidityLoop(liq: postSellLiq, needs: buyLiq, filterKeys: true) { exchange, _, key, ticker, value in
            var increment = 0
            if let index = buyLiq[key]?.firstIndex(where: { $0.0 == ticker.0 }) {
                if ticker.1 == value {
                    buyLiq[key]!.remove(at: index)
                    increment = 1
                } else {
                    buyLiq[key]![index].1 = buyLiq[key]![index].1 - value
                }
            }
            postSellLiq[exchange] = postSellLiq[exchange]! - value
            let buyKey = "\(ticker.0):\(exchange.rawValue)"
            buyTransactions[buyKey] = value + (buyTransactions[buyKey] ?? 0)
            return increment
        }

        var exchangeTransfers: [String : Double] = [:]
                
        liquidityLoop(liq: postSellLiq,
                      needs: buyLiq.filter { !$1.isEmpty },
                      decrement: true) { exchange, exchange2, key, ticker, value in
            if exchange != exchange2 {
                let tKey = "\(exchange.rawValue):\(exchange2.rawValue)"
                exchangeTransfers[tKey] = (exchangeTransfers[tKey] ?? 0.0) + value
            }
            let buyKey = "\(ticker.0):\(exchange2.rawValue)"
            buyTransactions[buyKey] = value + (buyTransactions[buyKey] ?? 0)
            return value == ticker.1 ? 1 : 0
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
    
    private func liquidityLoop(liq: [Exchange : Double],
                               needs: [Set<Exchange> : [(String, Double)]],
                               decrement: Bool = false, filterKeys: Bool = false,
                               _ block: (Exchange, Exchange, Set<Exchange>, (String, Double), Double) -> Int) {
        if needs.isEmpty { return }
        var i = 0, j = 0, needs = needs
        for (exchange, liquidity) in liq.shuffled() {
            var liquidity = liquidity
            let keys = needs.keys
                .filter { !filterKeys || $0.contains(exchange) }
                .shuffled()
            while liquidity > 0, i < keys.count {
                let key = keys[i], tickers = needs[key]!
                let exchange2 = key.randomElement()!
                while liquidity > 0, j < tickers.count {
                    let ticker = tickers[j], v = min(ticker.1, liquidity)
                    liquidity -= v
                    if decrement, j < needs[key]?.count ?? 0 {
                        needs[key]![j].1 = needs[key]![j].1 - v
                    }
                    j += block(exchange, exchange2, key, ticker, v)
                }
                if liquidity > 0 {
                    i += 1
                    j = 0
                }
            }
        }
    }

    
}

