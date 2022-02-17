//
//  JSONSchema.swift
//  BalanceBot
//
//  Created by Ben Gray on 16/02/2022.
//

import Foundation
import Combine
import SwiftyJSON

indirect enum JSONDecodeSchema {
    case repeatUnit([JSONDecodeSchema], fixed: [Any])
    case unwrap(JSONSubscriptType, JSONDecodeSchema)
    case value(JSONSubscriptType?)
    case key
}

extension Balance {
    struct ExchangeBalance: ArrayInitialisable, Equatable {
        var ticker: String
        var balance: Double
        var exchange: Exchange
        
        init(values: [Any]) throws {
            guard let ticker = values[0] as? String,
                  let balance = values[1] as? Double ?? Double(values[1] as? String ?? ""),
                  let exchange = values[2] as? Exchange,
                  let currency = exchange.currency(from: ticker, true) else {
                      print(("Invalid initialisation with vaues: \(values)"))
                      throw RegexError.noKeyPairFound
                  }
            self.ticker = currency
            self.balance = balance
            self.exchange = exchange
        }
        
    }
    
    struct Price: ArrayInitialisable, Equatable {
        var price: Double
        var ticker: String
        
        init(values: [Any]) throws {
            guard let price = values[0] as? Double ?? Double(values[0] as? String ?? ""),
                  let ticker = values[1] as? String,
                  let exchange = values[2] as? Exchange,
                  let currency = exchange.currency(from: ticker) else {
                      print(("Invalid initialisation with vaues: \(values)"))
                      throw RegexError.noKeyPairFound
                  }
            self.ticker = currency
            self.price = price
        }
        
    }
    
}

extension Exchange {
    
    var balancesSchema: JSONDecodeSchema {
        switch self {
        case .bitfinex: return .repeatUnit([.value(1), .value(2)], fixed: [self])
        case .kraken: return .unwrap("result", .repeatUnit([.key, .value(nil)], fixed: [self]))
        default: return .value("")
        }
    }
    
    var pricesSchema: JSONDecodeSchema {
        switch self {
        case .bitfinex: return .repeatUnit([.value(7), .value(0)], fixed: [self])
        case .kraken: return .unwrap("result", .repeatUnit([.unwrap("c", .value(0)), .key], fixed: [self]))
        default: return .value(nil)
        }
    }
    
}

extension JSON {
    
    func decode<Object: ArrayInitialisable>(to type: Object.Type, with schema: JSONDecodeSchema) throws -> [Object] {
        guard let objectValues = value(with: schema) as? [[Any]] else {
            throw RegexError.noKeyPairFound
        }
        return try objectValues.compactMap { try Object(values: $0) }
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
        case .unwrap(let key, let schema): return self[key].value(with: schema)
        case .value(let key) where key != nil: return self[key!].rawValue
        case .value: return rawValue
        case .key: return ""
        }
    }
    
}
