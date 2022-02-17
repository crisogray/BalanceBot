//
//  BalancesInteractor.swift
//  BalanceBot
//
//  Created by Ben Gray on 04/02/2022.
//

import Foundation
import Combine
protocol BalancesInteractor {
    func requestBalances(for account: Account)
}

struct ActualBalancesInteractor: BalancesInteractor {
    
    var appState: Store<AppState>
    var exchangeRepository: ExchangeRepository
    
    func requestBalances(for account: Account) {
        let cancelBag = CancelBag()
        appState[\.balances].setIsLoading(cancelBag: cancelBag)
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
            appState[\.balances] = .failed(error)
        } receiveValue: { balanceCollection in
            dump(balanceCollection.flatMap { $0 })
            appState[\.balances] = .loaded(balanceCollection.flatMap { $0 })
        }.store(in: cancelBag)
    }
    
}


extension Publishers {
    struct ZipMany<Element, F: Error>: Publisher {
        typealias Output = [Element]
        typealias Failure = F

        private let upstreams: [AnyPublisher<Element, F>]

        init(_ upstreams: [AnyPublisher<Element, F>]) {
            self.upstreams = upstreams
        }

        func receive<S: Subscriber>(subscriber: S) where Self.Failure == S.Failure, Self.Output == S.Input {
            let initial = Just<[Element]>([])
                .setFailureType(to: F.self)
                .eraseToAnyPublisher()

            let zipped = upstreams.reduce(into: initial) { result, upstream in
                result = result.zip(upstream) { elements, element in
                    elements + [element]
                }
                .eraseToAnyPublisher()
            }

            zipped.subscribe(subscriber)
        }
    }
}
