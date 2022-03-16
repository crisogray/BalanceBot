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
    @State var exchangeData: Loadable<ExchangeData> = .notRequested
    @State private var routingState: Routing = .init()
    private var routingBinding: Binding<Routing> {
        $routingState.dispatched(to: injection.appState, \.routing.dashboard)
    }
    
    var body: some View {
        content
            .onReceive(userSettingsUpdate) { userSettings = $0.loadedValue }
            .onReceive(exchangeUpdate) {
                exchangeData = $0
                if case let .loaded(exchangeData) = $0 {
                    injection.userSettingsInteractor
                        .updateBalances(exchangeData.balances, in: userSettings)
                }
            }
            .onReceive(routingUpdate) { routingState = $0 }
            .fullScreenCover(isPresented: routingBinding.apiKeys, content: { apiKeyView })
            .fullScreenCover(isPresented: routingBinding.strategy, content: { strategyView })
    }
    
    var content: AnyView {
        userSettings.account.connectedExchanges.isEmpty ?
        AnyView(connectExchangeView) : AnyView(containerStack(mainContent))
    }

}

// MARK: Views

extension DashboardView {
    
    var mainContent: AnyView {
        switch exchangeData {
        case .notRequested: return AnyView(notRequestedView)
        case .isLoading(last: let last, cancelBag: _) where last != nil:
            return AnyView(balancesView(last!))
        case .isLoading: return AnyView(loadingView)
        case let .failed(error): return AnyView(Text(error.localizedDescription))
        case let .loaded(exchangeData): return AnyView(balancesView(exchangeData))
        }
    }
    
    func containerStack(_ content: AnyView) -> some View {
        VStack {
            content
                .frame(maxHeight: .infinity)
            HStack {
                Spacer()
                dashboardButton(image: "slider.horizontal.3",
                                label: "Strategy",
                                action: showStrategy)
                    .disabled(exchangeData.value == nil)
                Spacer()
                dashboardButton(image: "key",
                                label: "API Keys",
                                action: showAPIKeys)
                Spacer()
            }.padding()
        }
    }
    
    var notRequestedView: some View {
        loadingView.onAppear {
            injection.exchangesInteractor.fetchExchangeData(for: userSettings.account)
        }
    }
    
    var loadingView: some View {
        ProgressView().progressViewStyle(CircularProgressViewStyle())
    }
    
    var apiKeyView: some View {
        APIKeysView(userSettings: userSettings,
                   isDisplayed: routingBinding.apiKeys)
            .environment(\.injection, injection)
    }
    
    var strategyView: some View {
        StrategyView(isDisplayed: routingBinding.strategy,
                     userSettings: userSettings, exchangeData: exchangeData.loadedValue)
            .environment(\.injection, injection)
    }
    
    var connectExchangeView: some View {
        VStack {
            Spacer()
            Text("BalanceBot").font(.title.bold())
            Spacer()
            Button(action: showAPIKeys) {
                Text("Connect an Exchange")
                    .font(.headline).padding()
                    .background(Color(.secondarySystemGroupedBackground))//red: 53 / 255, green: 53 / 255, blue: 53 / 255))
                    .cornerRadius(8)
            }
            Spacer()
        }
    }
    
    func balancesView(_ exchangeData: ExchangeData) -> some View {
        BalancesView(exchangeData: exchangeData)
    }
    
    func dashboardButton(image: String, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button(action: action) {
                Image(systemName: image)
                    .imageScale(.large)
                    .frame(width: 64, height: 64)
                    .background(Color(.secondarySystemGroupedBackground))//red: 53 / 255, green: 53 / 255, blue: 53 / 255))
                    .cornerRadius(32)
            }
            Text(label.uppercased())
                .font(.footnote.bold())
                .foregroundColor(Color(.gray))
        }
    }
    
}

// MARK: Functions

extension DashboardView {
    
    func showAPIKeys() {
        injection.appState[\.routing.dashboard.apiKeys] = true
    }
    
    func showStrategy() {
        injection.appState[\.routing.dashboard.strategy] = true
    }
    
}

// MARK: Routing

extension DashboardView {
    
    struct Routing: Equatable {
        var apiKeys = false
        var strategy = false
    }
    
}

// MARK: AppState Updates

extension DashboardView {
    
    var userSettingsUpdate: AnyPublisher<Loadable<UserSettings>, Never> {
        injection.appState.updates(for: \.userSettings)
    }
    
    var exchangeUpdate: AnyPublisher<Loadable<ExchangeData>, Never> {
        injection.appState.updates(for: \.exchangeData)
    }
    
    var routingUpdate: AnyPublisher<Routing, Never> {
        injection.appState.updates(for: \.routing.dashboard)
    }
    
}
