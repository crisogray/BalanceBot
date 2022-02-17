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
                return getBalances(on: exchange, with: key, and: secret)
                    .replaceError(with: [])
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
        ).sink { completion in
            guard case .failure(let error) = completion else { return }
            appState[\.balances] = .failed(error)
        } receiveValue: { balanceCollection in
            dump(balanceCollection)
            appState[\.balances] = .loaded(balanceCollection.flatMap { $0 })
        }.store(in: cancelBag)
    }
    
    func getBalances(on exchange: Exchange, with key: String, and secret: String) -> AnyPublisher<[Balance], Error> {
        exchangeRepository.getBalances(on: exchange, with: key, and: secret)
            .flatMap { exchangeBalances in
                Publishers.Zip(
                    Just(exchangeBalances).setFailureType(to: Error.self),
                    exchangeRepository.getPrices(for: exchangeBalances.map { $0.ticker }, on: exchange)
                ).eraseToAnyPublisher()
            }.flatMap { (exchangeBalances, prices) in
                Just(exchangeBalances.convertToBalances(prices))
                    .setFailureType(to: Error.self).eraseToAnyPublisher()
            }.eraseToAnyPublisher()
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
