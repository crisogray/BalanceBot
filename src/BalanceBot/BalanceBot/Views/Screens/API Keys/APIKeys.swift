//
//  APIKeyView.swift
//  BalanceBot
//
//  Created by Ben Gray on 08/02/2022.
//

import SwiftUI
import Combine

struct APIKeysView: View {
    
    @Environment(\.injection) private var injection: Injection
    @State var userSettings: UserSettings
    @State var removingExchange: Exchange?
    @Binding var isDisplayed: Bool
    
    var body: some View {
        NavigationView {
            content
                .navigationTitle("API Keys")
                .toolbar { closeToolbarItem }
                .onReceive(userSettingsUpdate) {
                    userSettings = $0.loadedValue
                    if case .loaded = $0 { removingExchange = nil }
                }
        }.accentColor(tintColor)
    }
    
}

// MARK: Views

extension APIKeysView {
    
    var content: some View {
        List {
            ForEach(Exchange.sortedAllCases, id: \.self) {
                if userSettings.account.connectedExchanges.keys.contains($0.rawValue) {
                    addedExchnageRow($0, index: Exchange.sortedAllCases.firstIndex(of: $0)!)
                } else {
                    exchangeRow($0)
                }
            }
        }.listStyle(PlainListStyle())
    }
    
    func addedExchnageRow(_ exchange: Exchange, index: Int) -> some View {
        exchangeRowContent(exchange, added: true)
            .swipeActions {
                Button("Remove") { remove(exchange) }
            }
    }
    
    func exchangeRow(_ exchange: Exchange) -> some View {
        ZStack {
            NavigationLink {
                APIKeyEntryView(exchange: exchange, userSettings: userSettings)
            } label: { EmptyView() }
            exchangeRowContent(exchange, added: false)
        }
    }
    
    func exchangeRowContent(_ exchange: Exchange, added: Bool) -> some View {
        HStack {
            Text(exchange.rawValue.uppercased())
                .font(.title2.weight(.bold))
                .foregroundColor(added ? .white : .gray)
                .padding(.vertical)
            Spacer()
            if added && removingExchange == exchange {
                ProgressView().progressViewStyle(CircularProgressViewStyle())
            } else {
                Image(systemName: added ? "checkmark.circle" : "plus.circle")
                    .imageScale(.large)
                    .foregroundColor(added ? .green : .white)
            }
        }
    }
    
    var closeToolbarItem: ToolbarItem<(), Button<Text>> {
        ToolbarItem(placement: .primaryAction) {
            Button("Close") {
                isDisplayed = false
            }
        }
    }
    
}

// MARK: Functions

extension APIKeysView {
    
    func remove(_ exchange: Exchange) {
        removingExchange = exchange
        injection.userSettingsInteractor
            .removeAPIKey(for: exchange, from: userSettings)
    }
    
}

// MARK: AppState Updates

extension APIKeysView {
    var userSettingsUpdate: AnyPublisher<Loadable<UserSettings>, Never> {
        injection.appState.updates(for: \.userSettings)
    }
}
