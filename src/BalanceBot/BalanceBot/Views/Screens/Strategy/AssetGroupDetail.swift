//
//  AssetGroupDetailView.swift
//  BalanceBot
//
//  Created by Ben Gray on 11/03/2022.
//

import SwiftUI

struct AssetGroupDetailView: View {
    
    @Environment(\.injection) private var injection: Injection
    @State var userSettings: UserSettings
    @State var exchangeData: ExchangeData
    @State var name: String
    @State var group: [String]
    @State var isLoading = false
    
    @FocusState var nameFocus: Bool
    
    var currentName: String?
    var currentGroup: [String]?
    
    var canSave: Bool {
        if let currentName = currentName,
           name.trimmed == currentName.trimmed,
           group == currentGroup {
            return false
        }
        return group.count > 1 && name.trimmed != "" && !tickers.contains(name.trimmed.uppercased())
    }
    
    private var tickers: [String] {
        exchangeData.tickers
            .map { $0.ticker }.unique.sorted(by: <)
    }
    
    var body: some View {
        content
            .navigationBarTitle("New Asset Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isLoading {
                        LoadingView()
                    } else {
                        Button("Save", action: saveGroup)
                            .disabled(!canSave)
                    }
                }
            }
    }
    
    var content: some View {
        Form {
            Section {
                TextField("Asset Group Name", text: $name)
                    .focused($nameFocus)
            }
            ForEach(tickers.notInReplacements(assetGroups()), id: \.self) {
                tickerRow($0)
            }
        }
    }
}

// MARK: Views

extension AssetGroupDetailView {
    
    func tickerRow(_ ticker: String) -> some View {
        Button {
            toggleTicker(ticker)
        } label: {
            HStack {
                Text(ticker).foregroundColor(.white)
                if group.contains(ticker) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                }
            }
        }
    }
    
}

// MARK: Functions

extension AssetGroupDetailView {
    
    func assetGroups() -> [String : [String]] {
        var assetGroups = userSettings.portfolio.assetGroups
        if let name = currentName {
            assetGroups.removeValue(forKey: name)
        }
        return assetGroups
    }
    
    func toggleTicker(_ ticker: String) {
        nameFocus = false
        if let index = group.firstIndex(of: ticker) {
            group.remove(at: index)
        } else {
            group.append(ticker)
        }
    }
    
    func saveGroup() {
        isLoading = true
        nameFocus = false
        if let oldName = currentName {
            injection.userSettingsInteractor
                .updateAssetGroup(oldName.trimmed, newName: name.trimmed,
                                  newGroup: group, in: userSettings)
        } else {
            injection.userSettingsInteractor
                .addAssetGroup(group, withName: name.trimmed, to: userSettings)
        }
    }
    
}
