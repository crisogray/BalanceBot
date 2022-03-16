//
//  UserSettingsInteractor.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import Combine
import CloudKit

protocol UserSettingsInteractor {
    func fetchUserSettings()
    
    // API Keys
    func addAPIKey(_ key: String, secret: String, for exchange: Exchange, to userSettings: UserSettings)
    func removeAPIKey(for exchange: Exchange, from userSettings: UserSettings)
    
    // Portfolio
    func updateBalances(_ balances: BalanceList, in userSettings: UserSettings)
    func updateTargetAllocation(_ targetAllocation: [String : Double], in userSettings: UserSettings)
    func updateRebalanceTrigger(_ rebalanceTrigger: RebalanceTrigger, in userSettings: UserSettings)
    func updateIsLive(_ isLive: Bool, in userSettings: UserSettings)
    
    // Asset Groups
    func addAssetGroup(_ group: [String], withName name: String, to userSettings: UserSettings)
    func updateAssetGroup(_ name: String, newName: String, newGroup: [String], in userSettings: UserSettings)
    func removeAssetGroup(_ name: String, from userSettings: UserSettings)
    
}

struct ActualUserSettingsInteractor: UserSettingsInteractor {
    
    let cloudKitRepository: CloudKitRepository
    let appState: Store<AppState>
    
    init(cloudKitRepository: CloudKitRepository,
         appState: Store<AppState>) {
        self.cloudKitRepository = cloudKitRepository
        self.appState = appState
    }

    // MARK: Initial Fetch
    
    func fetchUserSettings() {
        let cancelBag = CancelBag()
        appState[\.userSettings].setIsLoading(cancelBag: cancelBag)
        cloudKitRepository
            .fetchCurrentUserID()
            .map { $0.recordName.md5 }
            .flatMap { userId in
                getUserSettings(userId)
                    .catch { _ in createUserSettings(userId) }
            }.flatMap { userSettings in
                Publishers.Zip(
                    Result.Publisher(.success(userSettings)),
                    cloudKitRepository.hasNotifications(for: userSettings.1.recordID.recordName)
                ).eraseToAnyPublisher()
            }.sinkToUserSettings {
                appState[\.userSettings] = $0
            }.store(in: cancelBag)
    }
    
    func getUserSettings(_ id: String) -> AnyPublisher<(CKRecord, CKRecord), Error> {
        cloudKitRepository
            .fetchRecord(from: .priv, withId: id.ckRecordId)
            .flatMap { user -> AnyPublisher<(CKRecord, CKRecord), Error> in
                let userId = user["portfolio_id"] as! String
                return Publishers.Zip(
                    Result.Publisher(.success(user)),
                    cloudKitRepository.fetchRecord(from: .pub, withId: userId.ckRecordId)
                ).eraseToAnyPublisher()
        }.eraseToAnyPublisher()
    }
    
    func createUserSettings(_ id: String) -> AnyPublisher<(CKRecord, CKRecord), Error> {
        let account = Account.new(id), portfolio = Portfolio.new(account.portfolioId)
        return Publishers.Zip(
            cloudKitRepository.saveRecord(account.ckRecord, in: .priv),
            cloudKitRepository.saveRecord(portfolio.ckRecord, in: .pub)
        ).flatMap { userSettings in
            cloudKitRepository
                .subscribeToNotifications(for: portfolio.id)
                .flatMap { _ -> Result<(CKRecord, CKRecord), Error>.Publisher in
                    Result.Publisher(.success(userSettings))
                }.eraseToAnyPublisher()
        }.eraseToAnyPublisher()
        
        /*return cloudKitRepository.subscribeToNotifications(for: portfolio.id)
            .flatMap { _ in
                Publishers.Zip(
                    cloudKitRepository.saveRecord(account.ckRecord, in: .priv),
                    cloudKitRepository.saveRecord(portfolio.ckRecord, in: .pub)
                )
            }.eraseToAnyPublisher()*/
    }
    
    // MARK: Notifications
    
    func clearNotifications(for userSettings: UserSettings) {
        guard userSettings.hasNotifications else {
            return
        }
        let cancelBag = CancelBag()
        appState[\.userSettings].setIsLoading(cancelBag: cancelBag)
        cloudKitRepository
            .fetchNotifications(for: userSettings.portfolio.id)
            .flatMap { records in
                cloudKitRepository.deleteRecords(records.map(\.recordID), from: .pub)
            }.sink(receiveCompletion: { _ in
                appState[\.userSettings].cancelLoading()
            }) { _ in
                if case var .loaded(userSettings) = appState[\.userSettings] {
                    userSettings.hasNotifications = false
                    appState[\.userSettings] = .loaded(userSettings)
                }
            }.store(in: cancelBag)


    }
    
    // MARK: API Keys
    
    func addAPIKey(_ key: String, secret: String, for exchange: Exchange,
                   to userSettings: UserSettings) {
        update(userSettings, path: \.account.connectedExchanges[exchange.rawValue],
               value: ["key" : key, "secret" : secret])
    }
    
    func removeAPIKey(for exchange: Exchange, from userSettings: UserSettings) {
        let connectedExchanges = userSettings.account.connectedExchanges.filter {
            $0.key != exchange.rawValue
        }
        update(userSettings, path: \.account.connectedExchanges, value: connectedExchanges)
        updateTargetAllocation([:], in: userSettings)
    }
    
    // MARK: Portfolio
    
    func updateBalances(_ balances: BalanceList, in userSettings: UserSettings) {
        update(userSettings, path: \.portfolio.balances, isAccount: false,
               value: balances.grouped(by: \.ticker).mapValues { $0.total(\.balance) })
    }
        
    func updateTargetAllocation(_ targetAllocation: [String : Double], in userSettings: UserSettings) {
        var portfolio = userSettings.portfolio
        portfolio.targetAllocation = targetAllocation
        portfolio.isLive = 0
        update(userSettings, path: \.portfolio, isAccount: false, value: portfolio)
    }
        
    func updateRebalanceTrigger(_ rebalanceTrigger: RebalanceTrigger, in userSettings: UserSettings) {
        update(userSettings, path: \.portfolio.rebalanceTrigger, isAccount: false, value: rebalanceTrigger)
    }
    
    func updateIsLive(_ isLive: Bool, in userSettings: UserSettings) {
        update(userSettings, path: \.portfolio.isLive, isAccount: false, value: isLive ? 1 : 0)
    }
    
    func addAssetGroup(_ group: [String], withName name: String, to userSettings: UserSettings) {
        var portfolio = userSettings.portfolio
        portfolio.assetGroups[name] = group
        adjustTargetAllocation(&portfolio.targetAllocation, with: group, groupName: name)
        update(userSettings, path: \.portfolio, isAccount: false, value: portfolio)
    }
    
    func updateAssetGroup(_ name: String, newName: String, newGroup: [String], in userSettings: UserSettings) {
        var portfolio = userSettings.portfolio
        let group = portfolio.assetGroups.removeValue(forKey: name)
        portfolio.assetGroups[newName] = newGroup
        if let group = group {
            let newTickers = newGroup.filter { !group.contains($0) }
            if !newTickers.isEmpty || name != newName {
                adjustTargetAllocation(&portfolio.targetAllocation, with: newTickers,
                                       groupName: newName, oldName: name)
            }
        }
        update(userSettings, path: \.portfolio, isAccount: false, value: portfolio)
    }
    
    func adjustTargetAllocation(_ allocation: inout [String : Double], with newTickers: [String],
                                groupName: String, oldName: String? = nil) {
        var totalAllocation: Double = newTickers.compactMap { allocation.removeValue(forKey: $0) }.total
        if let oldName = oldName, let previousAllocation = allocation.removeValue(forKey: oldName) {
            totalAllocation += previousAllocation
        }
        allocation[groupName] = totalAllocation
    }
    
    func removeAssetGroup(_ name: String, from userSettings: UserSettings) {
        var portfolio = userSettings.portfolio
        portfolio.assetGroups.removeValue(forKey: name)
        if let _ = portfolio.targetAllocation[name] {
            portfolio.targetAllocation = [:]
            portfolio.isLive = 0
        }
        update(userSettings, path: \.portfolio, isAccount: false, value: portfolio)
    }
    
    // MARK: Update
    
    func update<T>(_ userSettings: UserSettings, path: WritableKeyPath<UserSettings, T>,
                   isAccount: Bool = true, value: T) {
        var settings = userSettings
        settings[keyPath: path] = value
        
        let cancelBag = CancelBag()
        appState[\.userSettings].setIsLoading(cancelBag: cancelBag)
        let record = isAccount ? settings.account.ckRecord : settings.portfolio.ckRecord
        cloudKitRepository
            .updateRecord(record, in: isAccount ? .priv : .pub)
            .sink { completion in
                appState[\.userSettings].cancelLoading()
            } receiveValue: { value in
                appState[\.userSettings] = .loaded(settings)
                if isAccount { appState[\.exchangeData] = .notRequested }
            }.store(in: cancelBag)
    }
    
}
