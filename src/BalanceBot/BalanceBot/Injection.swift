//
//  Injection.swift
//  BalanceBot
//
//  Created by Ben Gray on 05/02/2022.
//

import SwiftUI

struct Injection: EnvironmentKey {
    
    let appState: Store<AppState>
    let userPermissionsInteractor: UserPermissionsInteractor
    let userSettingsInteractor: UserSettingsInteractor
    let exchangesInteractor: ExchangesInteractor
    
    static var defaultValue: Self {
        let appState = Store<AppState>(AppState())
        let userPermissionsInteractor = ActualUserPermissionsInteractor(appState: appState)
        let userSettingsInteractor = ActualUserSettingsInteractor(cloudKitRepository: ActualCloudKitRepository(),
                                                                  keychainRepository: ActualKeychainRepository(),
                                                                  appState: appState)
        let exchangesInteractor = RealExchangesInteractor(appState: appState, exchangeRepository: ActualExchangeRepository())
        return .init(
            appState: appState,
            userPermissionsInteractor: userPermissionsInteractor,
            userSettingsInteractor: userSettingsInteractor,
            exchangesInteractor: exchangesInteractor
        )
    }
    
}

extension EnvironmentValues {
    var injection: Injection {
        get { self[Injection.self] }
        set { self[Injection.self] = newValue }
    }
}
