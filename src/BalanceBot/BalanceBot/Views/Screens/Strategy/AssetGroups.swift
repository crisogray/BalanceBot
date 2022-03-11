//
//  AssetGroupsView.swift
//  BalanceBot
//
//  Created by Ben Gray on 10/03/2022.
//

import SwiftUI
import Combine

struct AssetGroupsView: View {
    
    @Environment(\.injection) private var injection: Injection
    @State var userSettings: UserSettings
    @State var exchangeData: ExchangeData
    @State var selectedName: String? = nil
    @State var selectedGroup: [String]? = nil
    @State var showDetail = false
    @State var removingGroup: String?
    
    var body: some View {
        content
            .navigationTitle("Asset Groups")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(userSettingsUpdate) {
                if !$0.loadedValue.equals(userSettings, at: \.portfolio.assetGroups) {
                    showDetail = false
                    removingGroup = nil
                }
                userSettings = $0.loadedValue
            }
    }
    
    var content: AnyView {
        AnyView(assetGroupList)
    }
    
}

// MARK: Views

extension AssetGroupsView {
    
    var assetGroupList: some View {
        List {
            Section {
                assetGroupRow()
            }
            Section {
                ForEach(Array(userSettings.portfolio.assetGroups.keys), id: \.self) { name in
                    if name == removingGroup {
                        loadingRow(name)
                    } else {
                        assetGroupRow(name: name, group: userSettings.portfolio.assetGroups[name])
                            .swipeActions {
                                Button("Remove", action: { remove(name) })
                            }
                    }
                }
            }
        }.background {
            NavigationLink(isActive: $showDetail,
                           destination: { assetGroupDetailView },
                           label: { EmptyView() }).hidden()
        }
    }
    
    var assetGroupDetailView: some View {
        AssetGroupDetailView(userSettings: userSettings,
                             exchangeData: exchangeData,
                             name: selectedName ?? "", group: selectedGroup ?? [],
                             currentName: selectedName, currentGroup: selectedGroup)
            .environment(\.injection, injection)
    }
    
    func assetGroupRow(name: String? = nil, group: [String]? = nil) -> some View {
        HStack {
            Button(name ?? "New Asset Group") {
                selectedName = name
                selectedGroup = group
                showDetail = true
            }.foregroundColor(.white)
            Spacer()
            Image(systemName: name == nil ? "plus.circle" : "chevron.right")
        }
    }
    
    func loadingRow(_ name: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            LoadingView()
        }
    }
    

}
                   
// MARK: Functions

extension AssetGroupsView {
    
    func remove(_ group: String) {
        removingGroup = group
        injection.userSettingsInteractor
            .removeAssetGroup(group, from: userSettings)
    }
    
}

// MARK: AppState Updates

extension AssetGroupsView {
    
    var userSettingsUpdate: AnyPublisher<Loadable<UserSettings>, Never> {
        injection.appState.updates(for: \.userSettings)
    }
    
}

