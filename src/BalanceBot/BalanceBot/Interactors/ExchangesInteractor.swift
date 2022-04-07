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
                            _ total: Binding<Int>, _ progress: Binding<Int>, transactions: Binding<[Instruction]?>)
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
                    .filter { Exchange.allowedTickers.contains($0.ticker) }
                tickers.append(contentsOf: balances.map { Ticker([$0.ticker, $0.exchange])! }.filter { !tickers.contains($0)})
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
        let newTotal = total + delta, equilibrium = newTotal / Double(group.count)
        let offsides = balances.filter { (delta > 0) == ($1.total(\.usdValue) < equilibrium) }
        let target = (newTotal - (total - offsides.map { $1.total(\.usdValue) }.total)) / Double(offsides.count)
        return offsides.mapValues { target - $0.total(\.usdValue) }
    }
    
    /*
     
     Example:
     
     3 assets: $1000, $4000, $5000
     delta: -$4000
     old total: $10000
     new total: $6000
     equilibrium: $2000
     over equilibrium: [$4000, $5000]
     over total: $9000
     over target: (6000 - (10000 - 9000)) / 2 = 2500
     deltas: [2500 - 4000, 2500 - 50000] = [-$1500, -$2500]
     
     */
    
    private func currentAllocation(_ balances: BalanceList, _ portfolio: Portfolio) -> [String : Double] {
        let total = balances.total(\.usdValue)
        var allocation: [String : Double] = balances.grouped(by: \.ticker)
            .mapValues { 100.0 * $0.total(\.usdValue) / total }
        portfolio.assetGroups
            .filter { key, _ in portfolio.targetAllocation[key] != nil }
            .forEach { name, group in
                allocation[name] = group
                    .compactMap { allocation.removeValue(forKey: $0) }.total
            }
        portfolio.targetAllocation.keys
            .filter { allocation[$0] == nil }
            .forEach { allocation[$0] = 0.0 }
        return allocation
    }
    
    func calculateRebalance(for userSettings: UserSettings,
                            with exchangeData: ExchangeData,
                            _ iterations: Binding<Int>,
                            _ progress: Binding<Int>,
                            transactions: Binding<[Instruction]?>) {
        let total = exchangeData.balances.total(\.usdValue)
        let target = userSettings.portfolio.targetAllocation
        let current = currentAllocation(exchangeData.balances, userSettings.portfolio)
        
        var deltas: [String : Double] = [:]
        
        var ignoredDelta: Double = 0
        for ticker in Set(target.keys).union(Set(current.keys)) {
            let delta = (target[ticker] ?? 0) - (current[ticker] ?? 0)
            if abs(delta) < 1 {
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
        
        let count = deltas.count * 50 + exchangeData.balances.grouped(by: \.exchange).count * 200
        iterations.wrappedValue = count
        progress.wrappedValue = 0
        
        DispatchQueue.global().async {
            let solutions = (1...count).map { i -> [Instruction] in
                DispatchQueue.main.async { progress.wrappedValue = i }
                return transactionSolution(deltas, exchangeData: exchangeData)
            }
            let bestCount = solutions.sorted(by: { $0.count < $1.count }).first!.count
            let shortestSolutions = solutions
                .filter { $0.count == bestCount }
                .sorted { transferCount($0) < transferCount($1) }
            DispatchQueue.main.async { transactions.wrappedValue = shortestSolutions.first }
        }
    }
    
    private func transferCount(_ s: [Instruction]) -> Int {
        return s.filter { $0.command == .send }.count
    }
        
    // MARK: Part 2: Liquidity Matching
    
    private func transactionSolution(_ deltas: [String : Double],
                                     exchangeData: ExchangeData) -> [Instruction] {
        
        let balances = exchangeData.balances.grouped(by: \.ticker)
        var sellTransactions: [Instruction] = [], buyTransactions: [String : Instruction] = [:]
        var buyLiq: [Set<Exchange> : [(String, Double)]] = [:]
        var postSellLiq = (balances["USD"] ?? [])
            .reduce(into: [Exchange : Double]()) { $0[$1.exchange] = $1.usdValue }
        
        for (ticker, delta) in deltas.filter({ $1 > 0 }) {
            let exchanges = Set(exchangeData.tickers
                                    .compactMap { $0.ticker == ticker ? $0.exchange : nil })
            buyLiq[exchanges] = (buyLiq[exchanges] ?? []) + [(ticker, delta)]
        }
                
        for (ticker, delta) in deltas.filter({ $1 < 0 }) {
            let sellExchanges = (balances[ticker] ?? [])
                .map { ($0.exchange, max(-$0.usdValue, delta)) }.shuffled()
            var d = delta, i = 0
            while d < 0, i < sellExchanges.count {
                let (exchange, v) = sellExchanges[i], value = max(d, v)
                sellTransactions.append(.init(command: .sell, asset: ticker, usdValue: abs(value), exchange: exchange))
                postSellLiq[exchange] = (postSellLiq[exchange] ?? 0) + abs(value)
                d -= value
                i += value == v ? 1 : 0
            }
        }
        
        buyLiq = liquidityLoop(liq: postSellLiq, needs: buyLiq, filterKeys: true) { exchange, _, key, ticker, value in
            postSellLiq[exchange] = postSellLiq[exchange]! - value
            var instruction = Instruction(command: .buy, asset: ticker.0, usdValue: value, exchange: exchange)
            instruction.mergeWith(buyTransactions[instruction.key])
            buyTransactions[instruction.key] = instruction
        }.mapValues { $0.filter { v in v.1 > 0 } }.filter { !$1.isEmpty }

        var exchangeTransfers: [String : Instruction] = [:]
                
        _ = liquidityLoop(liq: postSellLiq, needs: buyLiq) { exchange, exchange2, key, ticker, value in
            if exchange != exchange2 {
                var instruction = Instruction(command: .send, usdValue: value, exchange: exchange, exchange2: exchange2)
                instruction.mergeWith(exchangeTransfers[instruction.key])
                exchangeTransfers[instruction.key] = instruction
            }
            var instruction = Instruction(command: .buy, asset: ticker.0, usdValue: value, exchange: exchange2)
            instruction.mergeWith(buyTransactions[instruction.key])
            buyTransactions[instruction.key] = instruction
        }
        
        return sellTransactions + exchangeTransfers.values + buyTransactions.values
    }
    
    private func liquidityLoop(
        liq: [Exchange : Double],
        needs: [Set<Exchange> : [(String, Double)]], filterKeys: Bool = false,
        _ block: (Exchange, Exchange, Set<Exchange>, (String, Double), Double) -> Void
    ) -> [Set<Exchange> : [(String, Double)]] {
        if needs.isEmpty { return needs }
        var i = 0, j = 0, needs = needs
        for (exchange, liquidity) in liq.shuffled() {
            var liquidity = liquidity
            let keys = needs.keys.filter { !filterKeys || $0.contains(exchange) }.shuffled()
            while liquidity > 0, i < keys.count {
                let key = keys[i]
                let e2 = key.contains(exchange) ? exchange : key.randomElement()!
                while liquidity > 0, j < needs[key]!.count {
                    let ticker = needs[key]![j], v = min(ticker.1, liquidity)
                    liquidity -= v
                    needs[key]![j].1 = needs[key]![j].1 - v
                    block(exchange, e2, key, ticker, v)
                    j += ticker.1 == v ? 1 : 0
                }
                if liquidity > 0 { i += 1; j = 0 }
            }
        }
        return needs
    }

}
