//
//  JSONSchema.swift
//  BalanceBot
//
//  Created by Ben Gray on 16/02/2022.
//

import SwiftyJSON

indirect enum JSONDecodeSchema {
    case repeatUnit([JSONDecodeSchema], fixed: [Any])
    case unwrap(JSONSubscriptType, JSONDecodeSchema)
    case value(JSONSubscriptType?)
    case key
}

protocol ArrayInitialisable {
    init?(_ values: [Any])
}

extension Balance: ArrayInitialisable {
    
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
    
    struct ExchangeBalance: ArrayInitialisable, Equatable {
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
    
    struct Price: ArrayInitialisable, Equatable {
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

extension Exchange {
    
    // ticker, balance, exchange
    // if complete request: ticker, balance, usdValue, exchange
    var balancesSchema: JSONDecodeSchema {
        switch self {
        case .bitfinex: return .repeatUnit([.value(1), .value(2)], fixed: [self])
        case .kraken: return .unwrap("result", .repeatUnit([.key, .value(nil)], fixed: [self]))
        case .coinbase: return .unwrap("data", .repeatUnit([.unwrap("balance", .value("currency")),
                                                            .unwrap("balance", .value("amount"))], fixed: [self]))
        case .ftx: return .unwrap("result", .repeatUnit([.value("coin"), .value("free"), .value("usdValue")], fixed: [self]))
        default: return .value("")
        }
    }
    
    // price, ticker, exchange
    var pricesSchema: JSONDecodeSchema {
        switch self {
        case .bitfinex: return .repeatUnit([.value(7), .value(0)], fixed: [self])
        case .kraken: return .unwrap("result", .repeatUnit([.unwrap("c", .value(0)), .key], fixed: [self]))
        case .coinbase: return .repeatUnit([.value("amount"), .value("base")], fixed: [self])
        default: return .value(nil)
        }
    }
    
}

extension JSON {
    
    func decode<Object: ArrayInitialisable>(
        to type: Object.Type, with schema: JSONDecodeSchema) -> [Object] {
        (value(with: schema) as? [[Any]] ?? []).compactMap { Object($0) }
    }
    
    private func value(with schema: JSONDecodeSchema) -> Any {
        switch schema {
        case let .repeatUnit(schemas, fixed):
            return map { key, value in
                schemas.map { schema -> Any in
                    if case .key = schema { return key }
                    else { return value.value(with: schema) }
                } + fixed
            }
        case let .unwrap(key, schema): return self[key].value(with: schema)
        case let .value(key) where key != nil: return self[key!].rawValue
        case .value: return rawValue
        default: return ""
        }
    }
    
}
