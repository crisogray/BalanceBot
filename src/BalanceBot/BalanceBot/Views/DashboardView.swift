//
//  DashboardView.swift
//  BalanceBot
//
//  Created by Ben Gray on 06/02/2022.
//

import SwiftUI
import Combine

struct DashboardView: View {
    
    @Environment(\.injected) private var injection: Injection
    var userSettings: UserSettings
    @State var balances: Loadable<[Balance]> = .notRequested
    
    var body: some View {
        content
            .onReceive(balancesUpdate) { balances = $0 }
    }
    
    var content: AnyView {
        AnyView(containerStack(mainContent))
    }

}

extension DashboardView {
    
    var mainContent: AnyView {
        if userSettings.account.connectedExchanges.isEmpty {
            return AnyView(Text("Connect an Exchange"))
        }
        switch balances {
        case .notRequested: return AnyView(Text("Please Request Balances"))
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
    
    func dashboardButton(_ type: DashboardButtonType) -> some View {
        VStack(spacing: 12) {
            Button {
                switch type {
                case .target: print("Show Target")
                case .keys: print("Show Keys")
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
    var balancesUpdate: AnyPublisher<Loadable<[Balance]>, Never> {
        injection.appState.updates(for: \.balances)
    }
}
