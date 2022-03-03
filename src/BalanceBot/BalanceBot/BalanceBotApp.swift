//
//  BalanceBotApp.swift
//  BalanceBot
//
//  Created by Ben Gray on 02/02/2022.
//

import SwiftUI

@main
struct BalanceBotApp: App {
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color(red: 244 / 255, green: 184 / 255, blue: 39 / 255))
                .environment(\.injection, Injection.defaultValue)
                .preferredColorScheme(.dark)
        }
    }
}
