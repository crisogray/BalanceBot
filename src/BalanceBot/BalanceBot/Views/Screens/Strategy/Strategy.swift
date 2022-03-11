//
//  StrategyView.swift
//  BalanceBot
//
//  Created by Ben Gray on 09/03/2022.
//

import SwiftUI
import Combine

struct StrategyView: View {
    
    @Environment(\.injection) private var injection: Injection
    @Binding var isDisplayed: Bool
    @State var userSettings: UserSettings
    @State var exchangeData: ExchangeData
    @State var targetAllocation: [String : Double] = [:]
    private var total: Double { Array(targetAllocation.values).total }
    
    var body: some View {
        NavigationView {
            content
                .navigationTitle("Strategy")
                .toolbar { closeToolbarItem }
                .onReceive(userSettingsUpdate) {
                    if !$0.loadedValue.equals(userSettings, at: \.portfolio.targetAllocation) {
                        targetAllocation = userSettings.portfolio.targetAllocation
                    }
                    userSettings = $0.loadedValue
                }
        }
        .onAppear { targetAllocation = userSettings.portfolio.targetAllocation  }
        .accentColor(tintColor)
    }
    
    @State var toggle = false
    @State var strategy = ""

}

// MARK: Views

extension StrategyView {
    
    var content: some View {
        VStack(spacing: 0) {
            List {
                Section(header: Text("Portfolio Settings")) {
                    Toggle("isLive", isOn: $toggle).font(.headline)
                        .disabled(targetAllocation != userSettings.portfolio.targetAllocation || total != 100)
                    Picker("Rebalance Trigger", selection: $strategy) {
                        Text("Threshold").tag("t")
                        Text("Calendar").tag("c")
                    }
                    NavigationLink("Asset Groups", destination: assetGroupsView)
                }
                Section(header: Text("Target Allocation")) {
                    let tickers = exchangeData
                        .tickers.map { $0.ticker }.unique
                        .withReplacements(userSettings.portfolio.assetGroups)
                    ForEach(tickers, id: \.self) { ticker in
                        let percentage = targetAllocation[ticker] ?? 0
                        tickerRow(ticker, percentage: percentage)
                            .foregroundColor(percentage > 0 ? .white : .gray)
                    }
                }
            }
            if targetAllocation != userSettings.portfolio.targetAllocation {
                HStack(spacing: 16) {
                    saveButton
                    allocationPercentage
                }
                .background(Color.clear).padding()
                .transition(.move(edge: .bottom))
            }
        }
    }
    
    func tickerRow(_ ticker: String, percentage: Double) -> some View {
        HStack {
            Stepper {
                VStack(alignment: .leading, spacing: 0) {
                    Text(ticker)
                        .font(.title2.bold())
                    if let subTickers = userSettings.portfolio.assetGroups[ticker] {
                        Text("\(subTickers.joined(separator: ", "))")
                            .font(.footnote)
                    }
                }.padding(.vertical)
            } onIncrement: { increment(ticker)
            } onDecrement: { decrement(ticker) }
            Spacer()
            Text("\(Int(percentage))%")
                .frame(width: 80, alignment: .trailing)
                .font(.title.weight(.heavy))
        }
    }
    
    var saveButton: some View {
        Button(action: saveTargetAllocation) {
            Text("Save Allocation")
                .frame(maxWidth: .infinity)
                .font(.headline).padding()
                .background(Color(.secondarySystemGroupedBackground))//(red: 53 / 255, green: 53 / 255, blue: 53 / 255))
                .cornerRadius(8)
        }.disabled(total != 100 || targetAllocation == userSettings.portfolio.targetAllocation)
    }
    
    var allocationPercentage:  some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("\(Int(total))").font(.largeTitle.bold())
            Text(" / 100%").font(.headline.weight(.heavy))
                .foregroundColor(Color(.darkGray))
                .padding(.bottom, 6)
        }
    }
    
    var closeToolbarItem: ToolbarItem<(), Button<Text>> {
        ToolbarItem(placement: .primaryAction) {
            Button("Close") {
                isDisplayed = false
            }
        }
    }
    
    var assetGroupsView: some View {
        AssetGroupsView(userSettings: userSettings, exchangeData: exchangeData)
            .environment(\.injection, injection)
    }
    
}

// MARK: Functions

extension StrategyView {
    
    func increment(_ ticker: String) {
        if let value = targetAllocation[ticker] {
            targetAllocation[ticker] = min(value + 5, 100)
        } else {
            withAnimation {
                targetAllocation[ticker] = 5
            }
        }
    }
    
    func decrement(_ ticker: String) {
        if let value = targetAllocation[ticker] {
            if value > 5 {
                targetAllocation[ticker] = value - 5
            } else {
                withAnimation {
                    _ = targetAllocation.removeValue(forKey: ticker)
                }
            }
        }
    }
    
    func saveTargetAllocation() {
        print("Save Allocation")
    }
    
}

// MARK: Appstate Updates

extension StrategyView {
    var userSettingsUpdate: AnyPublisher<Loadable<UserSettings>, Never> {
        injection.appState.updates(for: \.userSettings)
    }
}
