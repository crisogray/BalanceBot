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

// MARK: Equatable

extension Equatable {
    
    func equals<T: Equatable>(_ equatable: Self, at path: KeyPath<Self, T>) -> Bool {
        return self[keyPath: path] == equatable[keyPath: path]
    }
    
}

// MARK: String

extension String {
    
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
}

// MARK: Target Allocation

func adjustTargetAllocation(_ allocation: [String : Double], with newTickers: [String],
                            groupName: String) -> [String : Double] {
    var allocation = allocation
    let totalAllocation: [Double] = newTickers.compactMap {
        allocation.removeValue(forKey: $0)
    }
    allocation[groupName] = totalAllocation.total
    return allocation
}

// MARK: Array and Dictionary

extension Array where Element: Equatable {
    
    func sorted<T: Comparable>(_ keyPath: KeyPath<Element, T>, ascending: Bool = false) -> [Element] {
        sorted { ($0[keyPath: keyPath] > $1[keyPath: keyPath]) != ascending }
    }
    
    func grouped<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [T : [Element]] {
        .init(grouping: self, by: { $0[keyPath: keyPath] })
    }
    
    func notInReplacements<T: Hashable>(_ replacements: [T : [Element]]) -> [Element] {
        let values = replacements.values.flatMap { $0 }
        return filter { !values.contains($0) }
    }
    
    mutating func addUnique(contentsOf array: [Element]) {
        array.forEach { element in
            if !contains(element) {
                append(element)
            }
        }
    }
    
}

extension Sequence where Element: Hashable {
    
    var unique: [Element] {
        Array(Set(self))
    }
    
}

extension Dictionary where Value == BalanceList {
    var sortedKeys: [Key] { keys.sorted { self[$0]!.usdTotal > self[$1]!.usdTotal } }
}

extension Sequence where Element == String {
    func withReplacements(_ replacements: [String : [String]]) -> [Element] {
        var tickers = Array(self.sorted())
        tickers.insert(contentsOf: replacements.keys, at: 0)
        return tickers.notInReplacements(replacements)
    }
}
