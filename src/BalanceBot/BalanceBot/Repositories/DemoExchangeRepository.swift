//
//  DemoExchangeRepository.swift
//  BalanceBot
//
//  Created by Ben Gray on 18/03/2022.
//

import Foundation
import Combine

struct DemoExchangeRepository: ExchangeRepository {
    
    let actualExchangeRepository = ActualExchangeRepository()
    
    func getBalances(on exchange: Exchange, with key: String, and secret: String) -> AnyPublisher<[Balance], Error> {
        Just(exchange.balances).flatMap { exchangeBalances in
            Publishers.Zip(
                Result.Publisher(.success(exchangeBalances)),
                getPrices(for: exchangeBalances.map { $0.ticker }, on: exchange)
            ).eraseToAnyPublisher()
        }.flatMap { (exchangeBalances, prices) in
            Result<[Balance], Error>.Publisher(.success(exchangeBalances.convertToBalances(prices)))
        }.eraseToAnyPublisher()
    }
    
    func getPrices(for tickers: [String], on exchange: Exchange) -> AnyPublisher<[Balance.Price], Error> {
        actualExchangeRepository.getPrices(for: tickers, on: exchange)
    }
    
    func getTickers(on exchange: Exchange) -> AnyPublisher<[Ticker], Error> {
        Just(exchange.tickers).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
    
}

extension Exchange {
    
    private var demoTickers: [String] {
        switch self {
        case .bitfinex: return ["BTC", "ETH", "ADA", "LTC", "XMR"]
        case .ftx: return []
        case .kraken: return ["BTC", "SUSHI", "LTC", "XMR"]
        case .coinbase: return ["BTC", "ETH", "ZEC", "LTC"]
        }
    }
    
    private var demoBalances: [String : Double] {
        switch self {
        case .bitfinex: return ["BTC" : 0.6, "ADA" : 30000, "USD" : 2000]
        case .ftx: return [:]
        case .kraken: return ["ETH" : 1, "SUSHI" : 0, "USD" : 1000]
        case .coinbase: return ["BTC" : 0.5, "ETH" : 10, "ZEC" : 0.5, "USD" : 1000]
        }
    }
    
    var tickers: [Ticker] {
        demoTickers.map { Ticker([$0, self])! }
    }
    
    var balances: [Balance.ExchangeBalance] {
        demoBalances.map { Balance.ExchangeBalance([$0.0, $0.1, self])! }
    }
    
}


