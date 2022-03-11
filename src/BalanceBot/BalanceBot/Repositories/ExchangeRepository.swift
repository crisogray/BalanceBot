//
//  ExchangeRepository.swift
//  BalanceBot
//
//  Created by Ben Gray on 15/02/2022.
//

import Foundation
import Combine
import SwiftyJSON
import CryptoKit

protocol ExchangeRepository {
    func getBalances(on exchange: Exchange, with key: String, and secret: String) -> AnyPublisher<[Balance], Error>
    func getPrices(for tickers: [String], on exchange: Exchange) -> AnyPublisher<[Balance.Price], Error>
    func getTickers(on exchange: Exchange) -> AnyPublisher<[Ticker], Error>
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
    
    // MARK: Get Tickers
    
    func getTickers(on exchange: Exchange) -> AnyPublisher<[Ticker], Error> {
        return URLSession(configuration: .default)
            .dataTaskPublisher(for: API.getTickers(exchange).urlRequest)
            .tryMap {
                return try JSON(data: $0.data)
                    .decode(to: Ticker.self, with: exchange.tickersSchema)
            }
            .eraseToAnyPublisher()
    }
    
}

// MARK: API

extension ActualExchangeRepository {
    enum API {
        case getBalances(Exchange, String, String)
        case getPrices(Exchange, [String])
        case getTickers(Exchange)
    }
}

extension ActualExchangeRepository.API {
    
    var urlRequest: URLRequest {
        switch self {
        case let .getBalances(exchange, key, secret):
            return authenticatedRequest(exchange, key, secret)
        case let .getPrices(exchange, tickers):
            return pricesRequest(exchange, tickers: tickers)
        case let .getTickers(exchange):
            guard let url = URL(string: exchange.publicBaseURL + path(exchange)) else {
                fatalError("Invalid tickers URL")
            }
            return createRequest(exchange, url: url, headers: [:])
        }
    }
    
    // MARK: Path
    
    private func path(_ exchange: Exchange) -> String {
        switch (exchange, self) {
        case (.bitfinex, .getBalances): return "v2/auth/r/wallets"
        case (.bitfinex, .getPrices): return "tickers"
        case (.bitfinex, .getTickers): return "tickers?symbols=ALL"
        case (.kraken, .getBalances): return "private/Balance"
        case (.kraken, .getPrices): return "public/Ticker"
        case (.kraken, .getTickers): return "public/Assets"
        case (.coinbase, .getBalances): return "accounts"
        case (.coinbase, .getPrices(_, let tickers)): return "prices/\(tickers.first!)-USD/spot"
        case (.coinbase, .getTickers): return "currencies"
        case (.ftx, .getBalances): return "wallet/balances"
        case (.ftx, .getTickers): return "markets"
        default: return ""
        }
    }
    
    // MARK: Body
    
    private func body(_ exchange: Exchange) -> [String : String] {
        switch (exchange, self) {
        case (.kraken, .getBalances): return ["nonce" : String(Int(Date.now.timeIntervalSince1970))]
        default: return [:]
        }
    }
    
    // MARK: Method
    
    private func method(_ exchange: Exchange) -> String {
        switch (exchange, self) {
        case (.coinbase, .getBalances), (.ftx, .getBalances): return "GET"
        case (_, .getBalances): return "POST"
        default: return "GET"
        }
    }
    
    // MARK: Prices Requests
    
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
    
    // MARK: Authenticated Request
    
    private func authenticatedRequest(_ exchange: Exchange, _ key: String,
                                      _ secret: String) -> URLRequest {
        let body = body(exchange), path = path(exchange), method = method(exchange)
        let nonce = body["nonce"] ?? String(Int(Date.now.timeIntervalSince1970))
        let headers = createHeaders(exchange, path: path, body: body,
                                    key: key, secret: secret,
                                    nonce: nonce, method: method)
        guard let url = URL(string: exchange.authenticatedBaseUrl + path) else {
            fatalError("Invalid baseUrl and path in config for \(exchange.rawValue)")
        }
        return createRequest(exchange, url: url, headers: headers, body: body, method: method)
        
    }
    
    // MARK: Signature
    
    private func createHeaders(_ exchange: Exchange, path: String,
                               body: [String : String], key: String, secret: String,
                               nonce: String, method: String) -> [String : String] {
        switch exchange {
        case .bitfinex:
            let signature = signHMAC("/api/\(path)\(nonce)\(body.jsonString)",
                                              hmac: HMAC<SHA384>.self, secret: secret)
            return ["Content-Type": "application/json", "bfx-nonce": nonce,
                    "bfx-apikey": key, "bfx-signature": signature]
        case .kraken:
            let secretKey = SymmetricKey(data: Data(base64Encoded: secret)!)
            let digest = (nonce + body.queryString).data(using: .utf8)!
            let messagePath = "/0/\(path)".data(using: .utf8)! + SHA256.hash(data: digest)
            let signature = HMAC<SHA512>.authenticationCode(for: messagePath, using: secretKey)
            return ["API-Key" : key, "API-Sign" : Data(signature).base64EncodedString()]
        case .coinbase:
            let message = nonce + method + "/v2/\(path)" + (body.isEmpty ? "" : body.jsonString)
            let signature = signHMAC(message, hmac: HMAC<SHA256>.self, secret: secret)
            return ["Accept" : "application/json", "CB-ACCESS-KEY" : key,
                    "CB-ACCESS-TIMESTAMP" : nonce, "CB-ACCESS-SIGN" : signature]
        case .ftx:
            let nonce = String(Int(nonce)! * 1000)
            let message = nonce + method + "/api/\(path)"
            let signature = signHMAC(message, hmac: HMAC<SHA256>.self, secret: secret)
            return ["FTX-KEY" : key, "FTX-TS" : nonce, "FTX-SIGN" : signature]
        }
        
    }
    
    // MARK: HMAC
    
    private func signHMAC<H>(_ string: String, hmac: HMAC<H>.Type,
                             secret: String) -> String {
        let key = SymmetricKey(data: secret.data(using: .utf8)!)
        let signature = hmac.authenticationCode(for: string.data(using: .utf8)!, using: key)
        return Data(signature).map { String(format: "%02hhx", $0) }.joined()
    }
    
    // MARK: Request
    
    private func createRequest(_ exchange: Exchange, url: URL,
                               headers: [String : String],
                               body: [String : String]? = nil,
                               method: String = "GET") -> URLRequest {
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

