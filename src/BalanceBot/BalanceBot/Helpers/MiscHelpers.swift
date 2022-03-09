//
//  MiscHelpers.swift
//  BalanceBot
//
//  Created by Ben Gray on 09/03/2022.
//

import Foundation


extension Double {
    
    var usdFormat: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: self))!
    }
    
}

