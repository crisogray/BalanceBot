//
//  AppState.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import CloudKit

class AppState: Equatable {
    
    var userSettings: Loadable<UserSettings> = .notRequested
    var exchangeData: Loadable<ExchangeData> = .notRequested
    var permissions = Permissions()
    var routing = Routing()
    
}

extension AppState {
    
    struct Routing: Equatable {
        var dashboard = DashboardView.Routing()
    }
    
    struct Permissions: Equatable {
        var push: Permission.Status = .unknown
    }
}

func == (lhs: AppState, rhs: AppState) -> Bool {
    lhs.userSettings == rhs.userSettings &&
    lhs.exchangeData == rhs.exchangeData &&
    lhs.routing == rhs.routing
}
