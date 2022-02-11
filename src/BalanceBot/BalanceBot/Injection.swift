//
//  Injection.swift
//  BalanceBot
//
//  Created by Ben Gray on 05/02/2022.
//

import Foundation
import SwiftUI
import CloudKit

struct Injection: EnvironmentKey {
    
    let appState: Store<AppState>
    let userSettingsInteractor: UserSettingsInteractor
    let balancesInteractor: BalancesInteractor
    
    static var defaultValue: Self {
        let appState = Store<AppState>(AppState())
        let cloudKitRepository = ActualCloudKitRepository(container: CKContainer.default())
        let userSettingsInteractor = ActualUserSettingsInteractor(cloudKitRepository: cloudKitRepository,
                                                                  keychainRepository: ActualKeychainRepository(),
                                                                  appState: appState)
        return .init(appState: appState, userSettingsInteractor: userSettingsInteractor,
                     balancesInteractor: ActualBalancesInteractor())
    }
    
}

extension EnvironmentValues {
    var injection: Injection {
        get { self[Injection.self] }
        set { self[Injection.self] = newValue }
    }
}
