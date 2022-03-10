//
//  BalancesInteractor.swift
//  BalanceBot
//
//  Created by Ben Gray on 04/02/2022.
//

import Combine

protocol BalancesInteractor {
    func requestBalances(for account: Account)
}

struct ActualBalancesInteractor: BalancesInteractor {
    
    var appState: Store<AppState>
    var exchangeRepository: ExchangeRepository
    
    // MARK: Request Balances
    
    func requestBalances(for account: Account) {
        let cancelBag = CancelBag()
        appState[\.balanceList].setIsLoading(cancelBag: cancelBag)
        Publishers.ZipMany<[Balance], Error>(
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
    
}
