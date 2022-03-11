//
//  UserSettingsInteractor.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import Combine
import CloudKit

protocol UserSettingsInteractor {
    func fetchUserState()
    func addAPIKey(_ key: String, secret: String, for exchange: Exchange, to userSettings: UserSettings)
    func removeAPIKey(for exchange: Exchange, from userSettings: UserSettings)
    func updateBalances(_ balances: BalanceList, in userSettings: UserSettings)
    func addAssetGroup(_ group: [String], withName name: String, to userSettings: UserSettings)
    func updateAssetGroup(_ name: String, newName: String, group: [String], in userSettings: UserSettings)
    func removeAssetGroup(_ name: String, from userSettings: UserSettings)
}

struct ActualUserSettingsInteractor: UserSettingsInteractor {
    
    let cloudKitRepository: CloudKitRepository
    let keychainRepository: KeychainRepository
    let appState: Store<AppState>
    
    init(cloudKitRepository: CloudKitRepository,
         keychainRepository: KeychainRepository,
         appState: Store<AppState>) {
        self.cloudKitRepository = cloudKitRepository
        self.keychainRepository = keychainRepository
        self.appState = appState
    }

    // MARK: Initial Fetch
    
    func fetchUserState() {
        let cancelBag = CancelBag()
        appState[\.userSettings].setIsLoading(cancelBag: cancelBag)
        cloudKitRepository
            .fetchCurrentUserID()
            .map { $0.recordName.md5 }
            .flatMap { userId in
                getUserSettings(userId)
                    .catch { _ in createUserSettings(userId) }
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
        ).eraseToAnyPublisher()
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
    }
    
    // MARK: Portfolio
    
    func updateBalances(_ balances: BalanceList, in userSettings: UserSettings) {
        update(userSettings, path: \.portfolio.balances, isAccount: false,
               value: balances.grouped(by: \.ticker).mapValues { $0.usdTotal })
    }
        
    func updateTargetAllocation(_ targetAllocation: [String : Double], in userSettings: UserSettings) {
        var portfolio = userSettings.portfolio
        portfolio.targetAllocation = targetAllocation
        portfolio.isLive = 0
        update(userSettings, path: \.portfolio, isAccount: false, value: portfolio)
    }
        
    func updateRebalanceTrigger(_ rebalanceTrigger: String, in userSettings: UserSettings) {
        update(userSettings, path: \.portfolio.rebalanceTrigger, isAccount: false, value: rebalanceTrigger)
    }
    
    
    func updateIsLive(_ isLive: Bool, in userSettings: UserSettings) {
        update(userSettings, path: \.portfolio.isLive, isAccount: false, value: isLive ? 1 : 0)
    }
    
    func addAssetGroup(_ group: [String], withName name: String, to userSettings: UserSettings) {
        var assetGroups = userSettings.portfolio.assetGroups
        assetGroups[name] = group
        update(userSettings, path: \.portfolio.assetGroups, isAccount: false, value: assetGroups)
    }
    
    func updateAssetGroup(_ name: String, newName: String, group: [String], in userSettings: UserSettings) {
        var assetGroups = userSettings.portfolio.assetGroups
        assetGroups.removeValue(forKey: name)
        assetGroups[name] = group
        update(userSettings, path: \.portfolio.assetGroups, isAccount: false, value: assetGroups)
    }
    
    func removeAssetGroup(_ name: String, from userSettings: UserSettings) {
        var assetGroups = userSettings.portfolio.assetGroups
        assetGroups.removeValue(forKey: name)
        update(userSettings, path: \.portfolio.assetGroups, isAccount: false, value: assetGroups)
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
