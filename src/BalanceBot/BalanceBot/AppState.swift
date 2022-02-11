//
//  AppState.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import Foundation
import CloudKit

class AppState: Equatable {
    
    var userSettings: Loadable<UserSettings> = .notRequested
    var balances: Loadable<[Balance]> = .notRequested
    var routing = Routing()
    
    struct Routing {
        var dashboard = DashboardView.Routing()
    }
    
}

func == (lhs: AppState, rhs: AppState) -> Bool {
    return lhs.userSettings == rhs.userSettings &&
        lhs.balances == rhs.balances
}
