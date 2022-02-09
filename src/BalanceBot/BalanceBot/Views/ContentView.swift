//
//  ContentView.swift
//  BalanceBot
//
//  Created by Ben Gray on 02/02/2022.
//

import SwiftUI
import Combine

struct ContentView: View {
    
    @Environment(\.injected) private var injection: Injection
    @State var userSettings: Loadable<UserSettings> = .notRequested
    
    var body: some View {
        content.onReceive(authenticationUpdate) { userSettings = $0 }
    }
    
    var content: AnyView {
        switch userSettings {
        case .notRequested: return AnyView(notRequestedView)
        case .isLoading: return AnyView(loadingView)
        case .failed: return AnyView(notAuthenticatedView)
        case .loaded(let settings): return AnyView(dashboardView(settings))
        }
    }
    
}

extension ContentView {
    var notRequestedView: some View {
        Text("").onAppear { injection.userStateInteractor.fetchUserState() }
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
    var authenticationUpdate: AnyPublisher<Loadable<UserSettings>, Never> {
        injection.appState.updates(for: \.userSettings)
    }
}
