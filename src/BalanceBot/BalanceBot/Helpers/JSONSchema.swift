//
//  JSONSchema.swift
//  BalanceBot
//
//  Created by Ben Gray on 16/02/2022.
//

import SwiftyJSON

indirect enum JSONDecodeSchema {
    case repeatUnit([JSONDecodeSchema], fixed: [AnyHashable],
                    conditions: [(JSONDecodeSchema, AnyHashable)] = [])
    case unwrap(JSONSubscriptType, JSONDecodeSchema)
    case value(JSONSubscriptType? = nil)
    case key
}

protocol ArrayInitialised {
    init?(_ values: [Any])
}

extension Balance: ArrayInitialised {
    
    init?(_ values: [Any]) {
        guard let ticker = values[0] as? String, let exchange = values[3] as? Exchange,
              let balance = values[1] as? Double ?? Double(values[1] as? String ?? ""),
              let usdValue = values[2] as? Double ?? Double(values[2] as? String ?? ""),
              let currency = exchange.currency(from: ticker, true) else {
                  print("Invalid initialisation of Balance with vaues: \(values)")
                  return nil
              }
        self.ticker = currency
        self.balance = balance
        self.usdValue = usdValue
        self.price = usdValue / balance
        self.exchange = exchange
    }
    
}

extension Balance {
    
    struct ExchangeBalance: ArrayInitialised, Equatable {
        var ticker: String
        var balance: Double
        var exchange: Exchange
        
        init?(_ values: [Any]) {
            guard let ticker = values[0] as? String,
                  let balance = values[1] as? Double ?? Double(values[1] as? String ?? ""),
                  let exchange = values[2] as? Exchange,
                  let currency = exchange.currency(from: ticker, true) else {
                      print("Invalid initialisation of ExchangeBalance with vaues: \(values)")
                      return nil
                  }
            self.ticker = currency
            self.balance = balance
            self.exchange = exchange
        }
        
    }
    
    struct Price: ArrayInitialised, Equatable {
        var price: Double
        var ticker: String
        
        init?(_ values: [Any]) {
            guard let price = values[0] as? Double ?? Double(values[0] as? String ?? ""),
                  let ticker = values[1] as? String, let exchange = values[2] as? Exchange,
                  let currency = exchange.currency(from: ticker) else {
                      print("Invalid initialisation of Price with vaues: \(values)")
                      return nil
                  }
            self.ticker = currency
            self.price = price
        }
    }
    
}

struct Ticker: ArrayInitialised, Equatable {
    
    var ticker: String
    var exchange: Exchange
    
    init?(_ values: [Any]) {
        guard let ticker = values[0] as? String,
              let exchange = values[1] as? Exchange,
              let currency = exchange.currency(from: ticker) else {
                  print("Invalid initialisation of Ticker with vaues: \(values)")
                  return nil
              }
        self.ticker = exchange.renames[currency] ?? currency
        self.exchange = exchange
    }
    
}

extension Exchange {
    
    // ticker, balance, exchange
    // if complete request: ticker, balance, usdValue, exchange
    var balancesSchema: JSONDecodeSchema {
        switch self {
        case .bitfinex: return .repeatUnit([.value(1), .value(2)], fixed: [self],
                                           conditions: [(.value(0), "exchange")])
        case .kraken: return .unwrap("result", .repeatUnit([.key, .value(nil)], fixed: [self]))
        case .coinbase: return .unwrap("data", .repeatUnit([.unwrap("balance", .value("currency")),
                                                            .unwrap("balance", .value("amount"))], fixed: [self]))
        case .ftx: return .unwrap("result", .repeatUnit([.value("coin"), .value("free"), .value("usdValue")], fixed: [self]))
        }
    }
    
    // price, ticker, exchange
    var pricesSchema: JSONDecodeSchema {
        switch self {
        case .bitfinex: return .repeatUnit([.value(7), .value(0)], fixed: [self])
        case .kraken: return .unwrap("result", .repeatUnit([.unwrap("c", .value(0)), .key], fixed: [self]))
        case .coinbase: return .repeatUnit([.value("amount"), .value("base")], fixed: [self])
        default: return .value()
        }
    }
    
    var tickersSchema: JSONDecodeSchema {
        switch self {
        case .bitfinex: return .repeatUnit([.value(0)], fixed: [self])
        case .kraken: return .unwrap("result", .repeatUnit([.value("altname")], fixed: [self]))
        case .coinbase: return .unwrap("data", .repeatUnit([.value("id")], fixed: [self]))
        case .ftx: return .unwrap("result", .repeatUnit([.value("name")], fixed: [self],
                                                        conditions: [(.value("type"), "spot")]))
        }
    }
    
}

extension JSON {
    
    func decode<Object: ArrayInitialised>(to type: Object.Type,
                                            with schema: JSONDecodeSchema) -> [Object] {
        (value(with: schema) as? [[AnyHashable]] ?? []).compactMap { Object($0) }
    }
    
    private func value(with schema: JSONDecodeSchema) -> AnyHashable? {
        switch schema {
        case let .repeatUnit(schemas, fixed, conditions):
            return compactMap { key, value -> AnyHashable? in
                if conditions.contains(where: { value.value(with: $0) != $1}) { return nil }
                return schemas.compactMap { schema -> AnyHashable? in
                    if case .key = schema { return key }
                    else { return value.value(with: schema) }
                } + fixed
            }
        case let .unwrap(key, schema): return self[key].value(with: schema)
        case let .value(key) where key != nil: return self[key!].rawValue as? AnyHashable
        case .value: return rawValue as? AnyHashable
        default: return nil
        }
    }
    
}
