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
    
    func getBalances(on exchange: Exchange, with key: String, and secret: String) -> AnyPublisher<[Balance], Error> {
        let f = exchange.completeBalanceRequest ? completeBalanceRetrieval : twoStepBalanceRetrieval
        return f (URLSession(configuration: .default)
                    .dataTaskPublisher(for: API.getBalances(exchange, key, secret).urlRequest)
                    .tryMap { data, _ in
                        try JSON(data: data)
                    }.eraseToAnyPublisher(), exchange)
            .map { balanceList in balanceList.filter { $0.balance > 0 } }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            
    }
    
    private func completeBalanceRetrieval(_ publisher: AnyPublisher<JSON, Error>, _ exchange: Exchange) -> AnyPublisher<[Balance], Error> {
        publisher.map { json -> [Balance] in
            let balances = json.decode(to: Balance.self, with: exchange.balancesSchema)
            return balances
        }.eraseToAnyPublisher()
    }
    
    private func twoStepBalanceRetrieval(_ publisher: AnyPublisher<JSON, Error>, _ exchange: Exchange) -> AnyPublisher<[Balance], Error> {
        publisher.map { json -> [Balance.ExchangeBalance] in
            return json.decode(to: Balance.ExchangeBalance.self, with: exchange.balancesSchema)
        }.flatMap { exchangeBalances in
            Publishers.Zip(Just(exchangeBalances).setFailureType(to: Error.self),
                           getPrices(for: exchangeBalances.map { $0.ticker }, on: exchange))
                .eraseToAnyPublisher()
        }.flatMap { (exchangeBalances, prices) in
            Just(exchangeBalances.convertToBalances(prices))
                .setFailureType(to: Error.self).eraseToAnyPublisher()
        }.eraseToAnyPublisher()
    }
    
    func getPrices(for tickers: [String], on exchange: Exchange) -> AnyPublisher<[Balance.Price], Error> {
        if tickers.isEmpty {
            return Fail(error: RegexError.noKeyPairFound).eraseToAnyPublisher()
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
                    return try JSON(data: data).decode(to: Balance.Price.self, with: exchange.pricesSchema)
                }
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }
    }
    
}

extension ActualExchangeRepository {
    enum API {
        case getBalances(Exchange, String, String)
        case getPrices(Exchange, [String])
    }
    
}

extension ActualExchangeRepository.API {
    
    var urlRequest: URLRequest {
        switch self {
        case let .getBalances(exchange, key, secret):
            return authenticatedRequest(exchange, key, secret)
        case let .getPrices(exchange, tickers):
            return pricesRequest(exchange, tickers: tickers)
        }
    }
    
    private func path(_ exchange: Exchange) -> String {
        switch (exchange, self) {
        case (.bitfinex, .getBalances): return "v2/auth/r/wallets"
        case (.bitfinex, .getPrices): return "tickers"
        case (.kraken, .getBalances): return "private/Balance"
        case (.kraken, .getPrices): return "public/Ticker"
        case (.coinbase, .getBalances): return "accounts"
        case (.coinbase, .getPrices(_, let tickers)): return "prices/\(tickers.first!)-USD/spot"
        case (.ftx, .getBalances): return "wallet/balances"
        default: return ""
        }
    }
    
    private func body(_ exchange: Exchange) -> [String : String] {
        switch (exchange, self) {
        case (.kraken, .getBalances): return ["nonce" : String(Int(Date.now.timeIntervalSince1970))]
        default: return [:]
        }
    }
    
    private func method(_ exchange: Exchange) -> String {
        switch (exchange, self) {
        case (.coinbase, .getBalances), (.ftx, .getBalances): return "GET"
        case (_, .getBalances): return "POST"
        default: return "GET"
        }
    }
    
    private func pricesQuery(_ exchange: Exchange, tickers: [String]) -> String {
        let tickers = tickers.filter { $0 != "USD" }
        switch exchange {
        case .bitfinex: return "symbols=\(tickers.map { "t\($0)USD" }.joined(separator: ","))"
        case .kraken: return "pair=\(tickers.map { "\($0)USD" }.joined())"
        default: return ""
        }
    }
    
    private func pricesRequest(_ exchange: Exchange, tickers: [String]) -> URLRequest {
        let path = path(exchange), query = pricesQuery(exchange, tickers: tickers)
        guard let url = URL(string: "\(exchange.publicBaseURL + path)?\(query)") else {
            fatalError("Invalid url:\n" + "\(exchange.publicBaseURL + path)?\(query)")
        }
        return createRequest(exchange, url: url, headers: [:])
    }
    
    private func authenticatedRequest(_ exchange: Exchange, _ key: String, _ secret: String) -> URLRequest {
        let body = body(exchange), path = path(exchange), method = method(exchange)
        let nonce = body["nonce"] ?? String(Int(Date.now.timeIntervalSince1970))
        let headers = exchange.createHeaders(path: path, body: body, key: key, secret: secret, nonce: nonce, method: method)
        guard let url = URL(string: exchange.authenticatedBaseUrl + path) else {
            fatalError("Invalid baseUrl and path in config for \(exchange.rawValue)")
        }
        return createRequest(exchange, url: url, headers: headers, body: body, method: method)
        
    }
    
    private func createRequest(_ exchange: Exchange, url: URL, headers: [String : String], body: [String : String]? = nil, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        if let body = body, method != "GET" {
            switch exchange {
            case .coinbase: return request
            case .kraken: request.httpBody = body.queryString.data(using: .utf8)!
            default: request.httpBody = body.jsonData
            }
        }
        return request
    }
    
    
}

public extension Dictionary where Key: ExpressibleByStringLiteral, Value: ExpressibleByStringLiteral {
    var queryString: String {
        var postDataString = ""
        forEach { tuple in
            if postDataString.count != 0 {
                postDataString += "&"
            }
            postDataString += "\(tuple.key)=\(tuple.value)"
        }
        return postDataString
    }
}
