//
//  ExchangesInteractor.swift
//  BalanceBot
//
//  Created by Ben Gray on 04/02/2022.
//

import Combine

protocol ExchangesInteractor {
    func fetchExchangeData(for account: Account)
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
            }.eraseToAnyPublisher()
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
    
}

/*

 func requestBalances(for account: Account) -> AnyPublisher<BalanceList, Error> {
     let cancelBag = CancelBag()
     appState[\.balanceList].setIsLoading(cancelBag: cancelBag)
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
     ).sink { completion in
         guard case .failure(let error) = completion else {
             return
         }
         appState[\.balanceList] = .failed(error)
     } receiveValue: { balanceCollection in
         appState[\.balanceList] = .loaded(BalanceList(balanceCollection.flatMap { $0 }))
     }.store(in: cancelBag)
 }
 
 // MARK: Request Tickers
 
 func requestTickers(for userSettings: UserSettings) -> AnyPublisher {
     let cancelBag = CancelBag()
     binding.wrappedValue.setIsLoading(cancelBag: cancelBag)
     Publishers.ZipMany<[Ticker], Error>(
         userSettings.account.connectedExchanges.compactMap { exchangeName, keys in
             guard let exchange = Exchange(rawValue: exchangeName) else { return nil }
             return exchangeRepository.getTickers(on: exchange)
         }
     ).sink { completion in
         guard case .failure(let error) = completion else { return }
         binding.wrappedValue = .failed(error)
     } receiveValue: { tickers in
         var tickers = tickers.flatMap { $0 }.map { $0 }.filter { allowedTickers.contains($0.ticker) }
         // tickers.addUnique(contentsOf: balances.map { Ticker([])! } )
         binding.wrappedValue = .loaded(tickers)
     }.store(in: cancelBag)
 }
 
 */
