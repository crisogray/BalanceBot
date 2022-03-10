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
    @State var balances: BalanceList
    @State var targetAllocation: [String : Double] = [:]
    private var total: Int {
        .init(Array(targetAllocation.values).total)
    }
    
    var body: some View {
        NavigationView {
            content
                .navigationTitle("Strategy")
                .toolbar { closeToolbarItem }
                .onReceive(userSettingsUpdate) {
                    userSettings = $0.loadedValue
                }
        }.onAppear { targetAllocation = userSettings.portfolio.targetAllocation }
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
                        .disabled(targetAllocation != userSettings.portfolio.targetAllocation)
                    Picker("Rebalance Trigger", selection: $strategy) {
                        Text("Threshold").tag("t")
                        Text("Calendar").tag("c")
                    }
                    Text("Asset Groups").font(.headline)
                }
                Section(header: Text("Target Allocation")) {
                    ForEach(balances.grouped(by: \.ticker).sortedKeys, id: \.self) { ticker in
                        let percentage = targetAllocation[ticker] ?? 0
                        HStack {
                            Stepper {
                                Text(ticker)
                                    .font(.title2.bold())
                                    .foregroundColor(percentage > 0 ? .white : .gray)
                                    .padding(.vertical)
                            } onIncrement: { increment(ticker)
                            } onDecrement: { decrement(ticker) }
                            Spacer()
                            Text("\(Int(percentage))%")
                                .frame(width: 80, alignment: .trailing)
                                .font(.title.weight(.heavy))
                                .foregroundColor(percentage > 0 ? .white : .gray)
                        }
                    }
                }
            }
            if targetAllocation != userSettings.portfolio.targetAllocation {
                HStack(spacing: 16) {
                    Button(action: saveTargetAllocation) {
                        Text("Save Allocation")
                            .frame(maxWidth: .infinity)
                            .font(.headline).padding()
                            .background(Color(.secondarySystemGroupedBackground))//(red: 53 / 255, green: 53 / 255, blue: 53 / 255))
                            .cornerRadius(8)
                    }.disabled(total != 100)// || targetAllocation == userSettings.portfolio.targetAllocation)
                    HStack(alignment: .bottom, spacing: 0) {
                        Text("\(total)").font(.largeTitle.bold())
                        Text(" / 100%").font(.headline.weight(.heavy))
                            .foregroundColor(Color(.darkGray))
                            .padding(.bottom, 6)
                    }
                }.padding()
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

extension StrategyView {
    
    func increment(_ ticker: String) {
        let value = targetAllocation[ticker] ?? 0
        targetAllocation[ticker] = min(value + 5, 100)
    }
    
    func decrement(_ ticker: String) {
        if let value = targetAllocation[ticker] {
            if value > 5 { targetAllocation[ticker] = value - 5 }
            else { targetAllocation.removeValue(forKey: ticker) }
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
