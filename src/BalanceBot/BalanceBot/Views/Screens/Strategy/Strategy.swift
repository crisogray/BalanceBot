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
    
    // Input Variables
    @State var targetAllocation: [String : Double] = [:]
    @State var rebalanceTrigger: RebalanceTrigger = .calendar(.monthly)
    @State var rebalanceTriggerDetail: RebalanceTrigger = .calendar(.monthly)
    @State var isLive = false
    

    // Loadings
    @State var isLoadingTargetAllocation = false
    @State var isLoadingIsLive = false
    @State var firstAppear = true

    private var total: Double { Array(targetAllocation.values).total }
    
    var body: some View {
        NavigationView {
            content
                .navigationTitle("Strategy")
                .toolbar { closeToolbarItem }
                .onReceive(userSettingsUpdate, perform: handleUserSettingsUpdate)
                .onChange(of: isLive) { newValue in
                    if (userSettings.portfolio.isLive != 0) != newValue {
                        injection.userSettingsInteractor
                            .updateIsLive(newValue, in: userSettings)
                        isLoadingIsLive = true
                    }
                }
                .onChange(of: rebalanceTrigger) { newValue in
                    if !newValue.isSameType(as: rebalanceTriggerDetail) {
                        rebalanceTriggerDetail = newValue
                    }
                }
                .onChange(of: rebalanceTriggerDetail) { newValue in
                    if userSettings.portfolio.rebalanceTrigger != newValue {
                        injection.userSettingsInteractor
                            .updateRebalanceTrigger(newValue, in: userSettings)
                    }
                }
        }
        .onAppear {
            if firstAppear {
                targetAllocation = userSettings.portfolio.targetAllocation
                rebalanceTriggerDetail = userSettings.portfolio.rebalanceTrigger
                if case .calendar = userSettings.portfolio.rebalanceTrigger {
                    rebalanceTrigger = .calendar(.monthly)
                } else { rebalanceTrigger = .threshold(10) }
                isLive = userSettings.portfolio.isLive != 0
                firstAppear = false
            }
        }
        .accentColor(tintColor)
    }
    
}

// MARK: Views

extension StrategyView {
    
    var content: some View {
        VStack(spacing: 0) {
            List {
                Section(header: Text("Portfolio Settings")) {
                    Toggle("Strategy Active", isOn: $isLive)
                        .disabled(targetAllocation != userSettings.portfolio.targetAllocation || total != 100 || isLoadingIsLive)
                    Picker("Rebalance Trigger", selection: $rebalanceTrigger) {
                        Text("Calendar").tag(RebalanceTrigger.calendar(.monthly))
                        Text("Threshold").tag(RebalanceTrigger.threshold(10))
                    }
                    if case .calendar = rebalanceTrigger {
                        Picker("Regularity", selection: $rebalanceTriggerDetail) {
                            ForEach(RebalanceTrigger.CalendarSchedule.allCases, id: \.self) {
                                Text($0.displayString).tag(RebalanceTrigger.calendar($0))
                            }
                        }
                    } else {
                        Picker("Threshold", selection: $rebalanceTriggerDetail) {
                            ForEach(Array(stride(from: 5, through: 20, by: 5)), id: \.self) {
                                Text("\($0)%").tag(RebalanceTrigger.threshold($0))
                            }
                        }
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
                            .lineLimit(1)
                            .font(.footnote)
                    }
                }.padding(.vertical)
            } onIncrement: { increment(ticker) } onDecrement: { decrement(ticker) }
            Spacer()
            Text("\(Int(percentage))%")
                .frame(width: 80, alignment: .trailing)
                .font(.title.weight(.heavy))
        }.animation(.none, value: targetAllocation)
    }
    
    var saveButton: some View {
        Button(action: saveTargetAllocation) {
            Group {
                if isLoadingTargetAllocation { LoadingView() }
                else { Text("Save Allocation") }
            }
            .frame(maxWidth: .infinity)
            .font(.headline).padding()
            .background(Color(.secondarySystemGroupedBackground)) // (red: 53 / 255, green: 53 / 255, blue: 53 / 255))
            .cornerRadius(8)
        }.disabled(total != 100 ||
                   targetAllocation == userSettings.portfolio.targetAllocation ||
                   isLoadingTargetAllocation)
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
            Button("Close") { isDisplayed = false }
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
        let value = targetAllocation[ticker] ?? 0
        assignTicker(ticker, value: min(value + 5, 100))
    }
    
    func decrement(_ ticker: String) {
        if let value = targetAllocation[ticker], value > 5 {
            assignTicker(ticker, value: value - 5)
        } else if targetAllocation[ticker] != nil {
            withAnimation {
                _ = targetAllocation.removeValue(forKey: ticker)
            }
        }
    }
    
    func assignTicker(_ ticker: String, value: Double) {
        var test = targetAllocation
        test[ticker] = value
        if test == userSettings.portfolio.targetAllocation ||
            (targetAllocation == userSettings.portfolio.targetAllocation) {
            withAnimation {
                targetAllocation[ticker] = value
            }
        } else {
            targetAllocation[ticker] = value
        }
    }
    
    func saveTargetAllocation() {
        isLoadingTargetAllocation = true
        injection.userSettingsInteractor
            .updateTargetAllocation(targetAllocation, in: userSettings)
    }
    
    // Needs streamlining
    func handleUserSettingsUpdate(_ newSettings: Loadable<UserSettings>) {
        let newSettings = newSettings.loadedValue
        if !newSettings.equals(userSettings, at: \.portfolio.isLive) {
            isLoadingIsLive = false
            if isLive != (newSettings.portfolio.isLive != 0) {
                isLive = newSettings.portfolio.isLive != 0
            }
        }
        if !newSettings.equals(userSettings, at: \.portfolio.targetAllocation) {
            isLoadingTargetAllocation = false
            if targetAllocation != newSettings.portfolio.targetAllocation {
                targetAllocation = newSettings.portfolio.targetAllocation
            }
            withAnimation { userSettings = newSettings }
        } else if !newSettings.equals(userSettings, at: \.portfolio) &&
                    !newSettings.equals(userSettings, at: \.portfolio.targetAllocation) {
            targetAllocation = userSettings.portfolio.targetAllocation
        } else {
            userSettings = newSettings
        }
    }
    
}

// MARK: Appstate Updates

extension StrategyView {
    var userSettingsUpdate: AnyPublisher<Loadable<UserSettings>, Never> {
        injection.appState.updates(for: \.userSettings)
    }
}
