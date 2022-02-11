//
//  DashboardView.swift
//  BalanceBot
//
//  Created by Ben Gray on 06/02/2022.
//

import SwiftUI
import Combine

struct DashboardView: View {
    
    @Environment(\.injection) private var injection: Injection
    @State var userSettings: UserSettings
    @State var balances: Loadable<[Balance]> = .notRequested
    @State private var routingState: Routing = .init()
    private var routingBinding: Binding<Routing> {
        $routingState.dispatched(to: injection.appState, \.routing.dashboard)
    }
    
    var body: some View {
        content
            .onReceive(userSettingsUpdate) { userSettings = $0.loadedValue }
            .onReceive(balancesUpdate) { balances = $0 }
            .onReceive(routingUpdate) { routingState = $0 }
            .fullScreenCover(isPresented: routingBinding.apiKeysModal, content: { apiKeyView })
    }
    
    var content: AnyView {
        AnyView(containerStack(mainContent))
    }

}

extension DashboardView {
    
    var mainContent: AnyView {
        if userSettings.account.connectedExchanges.isEmpty {
            return AnyView(Text("Connect an Exchange to account: \(userSettings.account.id)"))
        }
        switch balances {
        case .notRequested: return AnyView(Text("Please Request Balances for account: \(userSettings.account.id)"))
        case .isLoading(last: _, cancelBag: _): return AnyView(Text("Loading"))
        case .failed(let error): return AnyView(Text(error.localizedDescription))
        case .loaded(let balances): return AnyView(Text("\(balances.count) Balances Loaded"))
        }
    }
    
    func containerStack(_ content: AnyView) -> some View {
        VStack {
            content
                .frame(maxHeight: .infinity)
            HStack {
                Spacer()
                dashboardButton(.target)
                    .disabled(userSettings.account.connectedExchanges.isEmpty)
                Spacer()
                dashboardButton(.keys)
                Spacer()
            }.padding()
        }
    }
    
    var apiKeyView: some View {
        APIKeyView(userSettings: userSettings, isDisplayed: routingBinding.apiKeysModal)
            .environment(\.injection, injection)
    }
    
    func dashboardButton(_ type: DashboardButtonType) -> some View {
        VStack(spacing: 12) {
            Button {
                switch type {
                case .target: print("Show Target")
                case .keys: showAPIKeys()
                }
            } label: {
                Image(systemName: type.imageSystemName)
                    .imageScale(.large)
                    .frame(width: 64, height: 64)
                    .background(Color(red: 53 / 255, green: 53 / 255, blue: 53 / 255))
                    .cornerRadius(32)
            }
            Text(type.displayName.uppercased())
                .font(.footnote.bold())
                .foregroundColor(Color(.gray))
        }
    }
    
    enum DashboardButtonType: String {
        
        case target, keys
        
        var displayName: String {
            switch self {
            case .keys: return "API Keys"
            case .target: return "Allocation"
            }
        }
        
        var imageSystemName: String {
            switch self {
            case .keys: return "key"
            case .target: return "slider.horizontal.3"
            }
        }
        
    }
    
}

extension DashboardView {
    
    func showAPIKeys() {
        injection.appState[\.routing.dashboard.apiKeysModal] = true
    }
    
}

extension DashboardView {
    
    struct Routing: Equatable {
        var apiKeysModal = false
    }
    
}

extension DashboardView {
    var userSettingsUpdate: AnyPublisher<Loadable<UserSettings>, Never> {
        injection.appState.updates(for: \.userSettings)
    }
    
    var balancesUpdate: AnyPublisher<Loadable<[Balance]>, Never> {
        injection.appState.updates(for: \.balances)
    }
    
    var routingUpdate: AnyPublisher<Routing, Never> {
        injection.appState.updates(for: \.routing.dashboard)
    }
    
}
