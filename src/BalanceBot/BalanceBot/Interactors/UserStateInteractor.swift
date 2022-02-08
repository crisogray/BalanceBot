//
//  CloudKitInteractor.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import Foundation
import Combine
import CloudKit

protocol UserStateInteractor {
    func fetchUserState()
    func getAccountPortfolioPair(_ id: CKRecord.ID) -> AnyPublisher<(CKRecord, CKRecord), Error>
    func createAccountPortfolioPair(_ id: CKRecord.ID) -> AnyPublisher<(CKRecord, CKRecord), Error>
}

struct ActualUserStateInteractor: UserStateInteractor {
    
    let cloudKitRepository: CloudKitRepository
    var appState: AppState
    
    init(cloudKitRepository: CloudKitRepository, appState: AppState) {
        self.cloudKitRepository = cloudKitRepository
        self.appState = appState
    }
    
    func fetchUserState() {
        var cancellables = Set<AnyCancellable>()
        appState.userState = .fetching
        cloudKitRepository
            .fetchCurrentUserID()
            .flatMap { id in
                getAccountPortfolioPair(id).catch { _ in
                    createAccountPortfolioPair(id)
                }
            }.sinkToUserState { userState in
                appState.userState = userState
            }.store(in: &cancellables)
    }
    
    func getAccountPortfolioPair(_ id: CKRecord.ID) -> AnyPublisher<(CKRecord, CKRecord), Error> {
        getAccount(id).flatMap { user in
            Publishers.Zip(
                Just(user).setFailureType(to: Error.self),
                getPortfolio(user["portfolio_id"] as! String)
            )
        }.eraseToAnyPublisher()
    }
    
    func getAccount(_ id: CKRecord.ID) -> AnyPublisher<CKRecord, Error> {
        cloudKitRepository.fetchRecord(from: .priv, withId: id)
    }
    
    func getPortfolio(_ id: String) -> AnyPublisher<CKRecord, Error> {
        cloudKitRepository.fetchRecord(from: .pub, withId: CKRecord.ID(recordName: id))
    }
    
    func createAccountPortfolioPair(_ id: CKRecord.ID) -> AnyPublisher<(CKRecord, CKRecord), Error> {
        let userRecord = createAccount(id)
        let portfolioRecord = createPortfolio(userRecord["portfoilio_id"] as! String)
        return Publishers.Zip(
            cloudKitRepository.saveRecord(userRecord, in: .priv),
            cloudKitRepository.saveRecord(portfolioRecord, in: .pub)
        ).eraseToAnyPublisher()
    }
    
    func createAccount(_ id: CKRecord.ID) -> CKRecord {
        let user = CKRecord(recordType: "Account", recordID: id)
        // Configure user record
        return user
    }
    
    func createPortfolio(_ id: String) -> CKRecord {
        let portfolio = CKRecord(recordType: "Portfolio", recordID: CKRecord.ID(recordName: id))
        // Configure portfolio
        return portfolio
    }
        
}

extension Publisher where Output == (CKRecord, CKRecord) {
    
    func sinkToUserState(_ sendUserState: @escaping (UserState) -> Void) -> AnyCancellable {
        return sink { completion in
            guard case .failure(_) = completion else { return }
            sendUserState(.notAuthenticated)
        } receiveValue: { value in
            sendUserState(.signedIn(account: value.0, portfolio: value.1))
        }

    }
    
}
