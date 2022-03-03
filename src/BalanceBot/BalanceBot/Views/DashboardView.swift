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
    @State var balanceList: Loadable<BalanceList> = .notRequested
    @State private var routingState: Routing = .init()
    private var routingBinding: Binding<Routing> {
        $routingState.dispatched(to: injection.appState, \.routing.dashboard)
    }
    
    var body: some View {
        content
            .onReceive(userSettingsUpdate) { userSettings = $0.loadedValue }
            .onReceive(balancesUpdate) { balanceList = $0 }
            .onReceive(routingUpdate) { routingState = $0 }
            .fullScreenCover(isPresented: routingBinding.apiKeysModal, content: { apiKeyView })
    }
    
    var content: AnyView {
        if userSettings.account.connectedExchanges.isEmpty {
            return AnyView(connectExchangeView)
        }
        return AnyView(containerStack(mainContent))
    }

}

extension DashboardView {
    
    var mainContent: AnyView {
        switch balanceList {
        case .notRequested: return AnyView(notRequestedView)
        case .isLoading(last: let last, cancelBag: _) where last != nil:
            return AnyView(balancesView(last!))
        case .isLoading: return AnyView(loadingView)
        case .failed(let error): return AnyView(Text(error.localizedDescription))
        case .loaded(let balances): return AnyView(balancesView(balances))
        }
    }
    
    func containerStack(_ content: AnyView) -> some View {
        VStack {
            content
                .frame(maxHeight: .infinity)
            HStack {
                Spacer()
                dashboardButton(image: "slider.horizontal.3", label: "Allocation") {
                    print("Show Target")
                }//.disabled(userSettings.account.connectedExchanges.isEmpty)
                Spacer()
                dashboardButton(image: "key", label: "API Keys", action: showAPIKeys)
                Spacer()
            }.padding()
        }
    }
    
    var notRequestedView: some View {
        Text("").onAppear { injection.balancesInteractor.requestBalances(for: userSettings.account) }
    }
    
    var loadingView: some View {
        ProgressView().progressViewStyle(CircularProgressViewStyle())
    }
    
    var apiKeyView: some View {
        APIKeyView(userSettings: userSettings, isDisplayed: routingBinding.apiKeysModal)
            .environment(\.injection, injection)
    }
    
    var connectExchangeView: some View {
        VStack {
            Spacer()
            Text("BalanceBot").font(.title.bold())
            Spacer()
            Button(action: showAPIKeys) {
                VStack {
                    Text("Connect an Exchange")
                        .font(.headline).padding()
                        .background(Color(red: 53 / 255, green: 53 / 255, blue: 53 / 255))
                        .cornerRadius(8)
                }
            }
            Spacer()
        }
    }
    
    func balancesView(_ balanceList: BalanceList) -> some View {
        VStack(alignment: .leading) {
            Text("Total Balance: $\(balanceList.total)")
            let groupedBalances = balanceList.groupedBy(\Balance.ticker)
            ForEach(Array(groupedBalances.keys), id: \.self) { ticker in
                let balanceList = groupedBalances[ticker]!
                let first = balanceList.balances.first!
                Text("\(ticker) - $\(balanceList.total) - $\(first.price)")
                ForEach(balanceList.balances, id: \.exchange) { balance in
                    Text("\t\(balance.exchange.rawValue) - \(balance.balance) - $\(balance.usdValue)")
                }
            }
        }
    }
    
    func dashboardButton(image: String, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button(action: action) {
                Image(systemName: image)
                    .imageScale(.large)
                    .frame(width: 64, height: 64)
                    .background(Color(red: 53 / 255, green: 53 / 255, blue: 53 / 255))
                    .cornerRadius(32)
            }
            Text(label.uppercased())
                .font(.footnote.bold())
                .foregroundColor(Color(.gray))
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
    
    var balancesUpdate: AnyPublisher<Loadable<BalanceList>, Never> {
        injection.appState.updates(for: \.balanceList)
    }
    
    var routingUpdate: AnyPublisher<Routing, Never> {
        injection.appState.updates(for: \.routing.dashboard)
    }
    
}
