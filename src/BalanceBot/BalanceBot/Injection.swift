//
//  Injection.swift
//  BalanceBot
//
//  Created by Ben Gray on 05/02/2022.
//

import Foundation
import SwiftUI

struct Injection: EnvironmentKey {
    
    let appState: Store<AppState>
    let userSettingsInteractor: UserSettingsInteractor
    let balancesInteractor: BalancesInteractor
    
    static var defaultValue: Self {
        let appState = Store<AppState>(AppState())
        let userSettingsInteractor = ActualUserSettingsInteractor(cloudKitRepository: ActualCloudKitRepository(),
                                                                  keychainRepository: ActualKeychainRepository(),
                                                                  appState: appState)
        let balancesInteractor = ActualBalancesInteractor(appState: appState, exchangeRepository: ActualExchangeRepository())
        return .init(
            appState: appState,
            userSettingsInteractor: userSettingsInteractor,
            balancesInteractor: balancesInteractor
        )
    }
    
}

extension EnvironmentValues {
    var injection: Injection {
        get { self[Injection.self] }
        set { self[Injection.self] = newValue }
    }
}
