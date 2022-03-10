//
//  Helpers.swift
//  BalanceBot
//
//  Created by Ben Gray on 09/03/2022.
//

import Foundation
import Combine

// MARK: ZipMany

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

// MARK: Number Formatting

extension Double {
    
    var usdFormat: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: self))!
    }
    
}

extension Array where Element == Double {
    var total: Double { reduce(0, +)}
}

