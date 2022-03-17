//
//  ExchangesInteractor.swift
//  BalanceBot
//
//  Created by Ben Gray on 04/02/2022.
//

import Foundation
import Combine

protocol ExchangesInteractor {
    func fetchExchangeData(for account: Account)
    func calculateRebalance(for userSettings: UserSettings, with exchangeData: ExchangeData)
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
    
    func calculateRebalance(for userSettings: UserSettings, with exchangeData: ExchangeData) {
        let total = exchangeData.balances.total(\.usdValue)
        let targetAllocation = userSettings.portfolio.targetAllocation
        let currentAllocation = currentAllocation(exchangeData.balances, userSettings.portfolio)
        
        let targetTickers = Set(targetAllocation.keys)
        let currentTickers = Set(currentAllocation.keys)
        
        var deltas: [String : Double] = [:]
        
        var ignoredDelta: Double = 0
        for ticker in currentTickers.union(targetTickers) {
            let delta = (targetAllocation[ticker] ?? 0) - (currentAllocation[ticker] ?? 0)
            if delta < 1 && delta > -1 {
                ignoredDelta += abs(delta)
            } else {
                if let group = userSettings.portfolio.assetGroups[ticker] {
                    let balances = exchangeData.balances.filter {
                        group.contains($0.ticker)
                    }.grouped(by: \.ticker)
                    deltasForGroup(group, balances: balances, delta: total * delta / 100).forEach {
                        deltas[$0] = $1
                    }
                } else if ticker != "USD" {
                    deltas[ticker] = total * delta / 100
                }
            }
        }
        deltas = deltas.mapValues {
            let share = total * ignoredDelta / Double(100 * deltas.count)
            return $0 < 0 ? min($0 + share, 0) : max($0 - share, 0)
        }
        deltas.forEach { (key, value) in
            if value > 0 {
                print("Buy \(value.usdFormat) of \(key)")
            } else {
                print("Sell \(abs(value).usdFormat) of \(key)")
            }
        }
    }
    
    private func deltasForGroup(_ group: [String], balances: [String : BalanceList], delta: Double) -> [String : Double] {
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

