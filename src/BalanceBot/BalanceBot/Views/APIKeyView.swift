//
//  APIKeyView.swift
//  BalanceBot
//
//  Created by Ben Gray on 08/02/2022.
//

import SwiftUI
import Combine

struct APIKeyView: View {
    
    @Environment(\.injection) private var injection: Injection
    @State var userSettings: UserSettings
    @State var removingExchange: Exchange?
    @Binding var isDisplayed: Bool
    
    var body: some View {
        NavigationView {
            exchangeList
                .navigationTitle("API Keys")
                .toolbar { closeToolbarItem }
                .onReceive(userSettingsUpdate) {
                    userSettings = $0.loadedValue
                    if case .loaded = $0 { removingExchange = nil }
                }
        }
    }
    
}

extension APIKeyView {
    
    var exchangeList: some View {
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
                Button("Remove") {
                    removingExchange = exchange
                    removeAPIKey(at: [index])
                }
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
                .font(.title.weight(.bold))
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

extension APIKeyView {
    func removeAPIKey(at offsets: IndexSet) {
        if let offset = offsets.first {
            let exchange = Exchange.sortedAllCases[offset]
            injection.userSettingsInteractor.removeAPIKey(for: exchange, from: userSettings)
        }
    }
}

extension APIKeyView {
    var userSettingsUpdate: AnyPublisher<Loadable<UserSettings>, Never> {
        injection.appState.updates(for: \.userSettings)
    }
}
