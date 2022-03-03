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

    func fetchUserState() {
        let cancelBag = CancelBag()
        appState[\.userSettings].setIsLoading(cancelBag: cancelBag)
        cloudKitRepository
            .fetchCurrentUserID()
            .map { $0.recordName.md5 }
            .flatMap { userId in
                getUserSettings(userId)
                    .catch { _ in createUserSettings(userId) }
            }.sinkToUserSettings { userSettings in
                appState[\.userSettings] = userSettings
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
    
    func addAPIKey(_ key: String, secret: String,
                   for exchange: Exchange,
                   to userSettings: UserSettings) {
        var settings = userSettings
        settings.account.connectedExchanges[exchange.rawValue] = ["key" : key, "secret" : secret]
        update(settings)
    }
    
    func removeAPIKey(for exchange: Exchange, from userSettings: UserSettings) {
        var settings = userSettings
        if let _ = settings.account.connectedExchanges.removeValue(forKey: exchange.rawValue) {
            update(settings)
        }
    }
    
    func update(_ userSettings: UserSettings, portfolio: Bool = false) {
        let cancelBag = CancelBag()
        appState[\.userSettings].setIsLoading(cancelBag: cancelBag)
        let record = portfolio ? userSettings.portfolio.ckRecord : userSettings.account.ckRecord
        cloudKitRepository
            .updateRecord(record, in: portfolio ? .pub : .priv)
            .sink { completion in
                appState[\.userSettings].cancelLoading()
            } receiveValue: { value in
                appState[\.userSettings] = .loaded(userSettings)
                if !portfolio {
                    appState[\.balanceList] = .notRequested
                }
            }.store(in: cancelBag)
    }
    
}

extension Publisher where Output == (CKRecord, CKRecord) {
    
    func sinkToUserSettings(_ sendUserSettings: @escaping (Loadable<UserSettings>) -> Void) -> AnyCancellable {
        return sink { completion in
            guard case .failure(let error) = completion else { return }
            sendUserSettings(.failed(error))
        } receiveValue: { value in
            sendUserSettings(.loaded(UserSettings(account: Account.fromCKRecord(value.0),
                                                  portfolio: Portfolio.fromCKRecord(value.1))))
        }
    }
    
}
