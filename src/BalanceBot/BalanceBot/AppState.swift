//
//  AppState.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import CloudKit

class AppState: Equatable {
    
    var userSettings: Loadable<UserSettings> = .notRequested
    var balanceList: Loadable<BalanceList> = .notRequested
    var routing = Routing()
    
    struct Routing: Equatable {
        var dashboard = DashboardView.Routing()
    }
    
}

func == (lhs: AppState, rhs: AppState) -> Bool {
    lhs.userSettings == rhs.userSettings &&
    lhs.balanceList == rhs.balanceList &&
    lhs.routing == rhs.routing
}
