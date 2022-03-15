//
//  ContentView.swift
//  BalanceBot
//
//  Created by Ben Gray on 02/02/2022.
//

import SwiftUI
import Combine

struct ContentView: View {
    
    @Environment(\.injection) private var injection: Injection
    @State var userSettings: Loadable<UserSettings> = .notRequested
    @State var permissionsStatus: Permission.Status = .unknown
    
    var body: some View {
        permissionsGate
            .onReceive(userSettingsUpdate) { userSettings = $0 }
            .onReceive(permissionsUpdate) { permissionsStatus = $0 }
    }
    
    var permissionsGate: AnyView {
        switch permissionsStatus {
        case .unknown, .notRequested: return AnyView(permissionsView)
        default: return content
        }
    }
    
    var content: AnyView {
        switch userSettings {
        case .notRequested: return AnyView(notRequestedView)
        case .failed: return AnyView(notAuthenticatedView)
        case .isLoading(last: let last, cancelBag: _) where last != nil:
            return AnyView(dashboardView(last!))
        case .isLoading: return AnyView(loadingView)
        case let .loaded(settings): return AnyView(dashboardView(settings))
        }
    }
    
}

extension ContentView {
    
    var notRequestedView: some View {
        Text("").onAppear {
            injection.userSettingsInteractor.fetchUserSettings()
        }
    }
    
    var permissionsView: some View {
        Text("")
            .onAppear {
                injection.userPermissionsInteractor.fetchPushNotificationsPermissionStatus()
            }.onChange(of: permissionsStatus) { newValue in
                if newValue == .notRequested {
                    injection.userPermissionsInteractor.requestPushNotificationsPermission()
                }
            }
    }
    
    var loadingView: some View {
        ProgressView().progressViewStyle(CircularProgressViewStyle())
    }
    
    var notAuthenticatedView: some View {
        Text("Not Authenticated")
    }
    
    func dashboardView(_ userSettings: UserSettings) -> some View {
        DashboardView(userSettings: userSettings)
    }
    
}

extension ContentView {
    var userSettingsUpdate: AnyPublisher<Loadable<UserSettings>, Never> {
        injection.appState.updates(for: \.userSettings)
    }
    
    var permissionsUpdate: AnyPublisher<Permission.Status, Never> {
        injection.appState.updates(for: \.permissions.push)
    }
}
