//
//  ExchangeRepository.swift
//  BalanceBot
//
//  Created by Ben Gray on 15/02/2022.
//

import Foundation
import Combine
import SwiftyJSON

protocol ExchangeRepository {
    func getBalances(on exchange: Exchange, with key: String, and secret: String) -> AnyPublisher<[Balance], Error>
    func getPrices(for tickers: [String], on exchange: Exchange) -> AnyPublisher<[Balance.Price], Error>
}

struct ActualExchangeRepository: ExchangeRepository {
    
    // MARK: Get Balances
    
    func getBalances(on exchange: Exchange, with key: String,
                     and secret: String) -> AnyPublisher<[Balance], Error> {
        let balancesFromJSON = exchange.balancesInOneStep ? oneStepBalances : twoStepBalances
        let jsonPublisher = URLSession(configuration: .default)
            .dataTaskPublisher(for: API.getBalances(exchange, key, secret).urlRequest)
            .tryMap { try JSON(data: $0.data) }
            .eraseToAnyPublisher()
        return balancesFromJSON(jsonPublisher, exchange)
            .map { balanceList in balanceList.filter { $0.balance > 0 } }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    private func oneStepBalances(_ publisher: AnyPublisher<JSON, Error>,
                                 _ exchange: Exchange) -> AnyPublisher<[Balance], Error> {
        publisher.map { json -> [Balance] in
            return json.decode(to: Balance.self, with: exchange.balancesSchema)
        }.eraseToAnyPublisher()
    }
    
    private func twoStepBalances(_ publisher: AnyPublisher<JSON, Error>,
                                 _ exchange: Exchange) -> AnyPublisher<[Balance], Error> {
        publisher.map { json -> [Balance.ExchangeBalance] in
            return json.decode(to: Balance.ExchangeBalance.self, with: exchange.balancesSchema)
        }.flatMap { exchangeBalances in
            Publishers.Zip(Result.Publisher(.success(exchangeBalances)),
                           getPrices(for: exchangeBalances.map { $0.ticker }, on: exchange))
                .eraseToAnyPublisher()
        }.flatMap { (exchangeBalances, prices) in
            Result<[Balance], Error>.Publisher(.success(exchangeBalances.convertToBalances(prices)))
        }.eraseToAnyPublisher()
    }
    
    // MARK: Get Prices
    
    func getPrices(for tickers: [String], on exchange: Exchange) -> AnyPublisher<[Balance.Price], Error> {
        if tickers.isEmpty {
            return Fail(error: AppError.invalidRequest).eraseToAnyPublisher()
        } else if exchange.singlePriceRequest && tickers.count > 1 {
            return Publishers.ZipMany<Balance.Price?, Error>(
                tickers.filter { $0 != "USD" }.map { ticker in
                    return getPrices(for: [ticker], on: exchange)
                        .map { $0.first } .eraseToAnyPublisher()
                }
            ).map { prices in prices.compactMap { $0 } }.eraseToAnyPublisher()
        } else {
            return URLSession(configuration: .default)
                .dataTaskPublisher(for: API.getPrices(exchange, tickers).urlRequest)
                .tryMap { data, _ in
                    return try JSON(data: data).decode(to: Balance.Price.self,
                                                       with: exchange.pricesSchema)
                }
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }
    }
    
}
