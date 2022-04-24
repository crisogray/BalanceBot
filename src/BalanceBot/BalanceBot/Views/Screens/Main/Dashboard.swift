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
    @State var isLoadingRebalance = false
    @State var rebalanceTransactions: [Instruction]? = nil
    @State var rebalanceTotal = 0
    @State var rebalanceProgress = 0
    @State var showRebalance = false
    @State private var routingState: Routing = .init()
    private let w = UIScreen.main.bounds.width
    private var routingBinding: Binding<Routing> {
        $routingState.dispatched(to: injection.appState, \.routing.dashboard)
    }
    
    var body: some View {
        content
            .onReceive(userSettingsUpdate) { userSettings = $0.loadedValue }
            .onReceive(exchangeUpdate) {
                if case let .loaded(exchangeData) = $0, exchangeData.balances != self.exchangeData.value?.balances {
                    injection.userSettingsInteractor
                        .updateBalances(exchangeData.balances, in: userSettings)
                }
                exchangeData = $0
            }
            .onReceive(routingUpdate) { routingState = $0 }
            .onChange(of: rebalanceTransactions) { newValue in
                isLoadingRebalance = false
                showRebalance = newValue != nil
            }
            .fullScreenCover(isPresented: routingBinding.apiKeys) { apiKeyView }
            .fullScreenCover(isPresented: routingBinding.strategy) { strategyView }
            .fullScreenCover(isPresented: $showRebalance) {
                if let instructions = rebalanceTransactions {
                    Rebalance(instructions: instructions, isDisplayed: $showRebalance)
                }
            }
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
        case let .isLoading(last: last, cancelBag: _) where last != nil:
            return AnyView(loadedView(userSettings, last!))
        case .isLoading: return AnyView(loadingView)
        case let .failed(error): return AnyView(Text(error.localizedDescription))
        case let .loaded(exchangeData): return AnyView(loadedView(userSettings, exchangeData))
        }
    }
    
    func containerStack(_ content: AnyView) -> some View {
        VStack {
            content.frame(maxHeight: .infinity)
            if isLoadingRebalance {
                ProgressView(value: Double(rebalanceProgress), total: Double(rebalanceTotal))
                    .frame(width: 192 + (w - 192) * 0.4)
            }
            HStack {
                Spacer()
                dashboardButton(image: "slider.horizontal.3",
                                label: "Strategy",
                                action: showStrategy)
                    .disabled(exchangeData.value == nil || isLoadingRebalance)
                Spacer()
                if isLoadingRebalance {
                    buttonStack("Rebalance") {
                        dashboardButtonStyle { LoadingView() }
                    }
                } else {
                    dashboardButton(image: "arrow.up.arrow.down",
                                    label: "Rebalance",
                                    action: calculateRebalance)
                        .disabled(exchangeData.value == nil || isLoadingRebalance ||
                                  userSettings.portfolio.targetAllocation.isEmpty)
                }
                Spacer()
                dashboardButton(image: "key",
                                label: "API Keys",
                                action: showAPIKeys)
                    .disabled(isLoadingRebalance)
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
    
    func loadedView(_ userSettings: UserSettings, _ exchangeData: ExchangeData) -> some View {
        BalancesView(exchangeData: exchangeData)
    }
    
    func dashboardButton(image: String, label: String, action: @escaping () -> Void) -> some View {
        buttonStack(label) {
            Button(action: action) {
                dashboardButtonStyle {
                    Image(systemName: image)
                        .imageScale(.large)
                }
            }
        }
    }
    
    func dashboardButtonStyle<V: View>(_ content: () -> V) -> some View {
        content()
            .frame(width: 64, height: 64)
            .background(Color(.secondarySystemGroupedBackground))//red: 53 / 255, green: 53 / 255, blue: 53 / 255))
            .cornerRadius(32)
    }
    
    func buttonStack<V: View>(_ label: String, content: () -> V) -> some View {
        VStack(spacing: 12) {
            content()
            Text(label.uppercased())
                .font(.footnote.bold())
                .foregroundColor(Color(.gray))
        }
    }
    
}

// MARK: Functions

extension DashboardView {
    
    func calculateRebalance() {
        isLoadingRebalance = true
        injection.exchangesInteractor
            .calculateRebalance(for: userSettings, with: exchangeData.loadedValue,
                                   $rebalanceTotal, $rebalanceProgress,
                                   transactions: $rebalanceTransactions)
    }
    
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
