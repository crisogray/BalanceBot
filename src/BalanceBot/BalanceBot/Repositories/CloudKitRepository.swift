//
//  CloudKitRepository.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import Combine
import CloudKit

typealias Completion<A> = (A?, Error?) -> Void

protocol CloudKitRepository {
    func fetchCurrentUserID() -> AnyPublisher<CKRecord.ID, Error>
    func fetchRecord(from database: CloudKitDatabase, withId id: CKRecord.ID) -> AnyPublisher<CKRecord, Error>
    func saveRecord(_ record: CKRecord, in database: CloudKitDatabase) -> AnyPublisher<CKRecord, Error>
    func updateRecord(_ record: CKRecord, in database: CloudKitDatabase) -> AnyPublisher<CKRecord, Error>
    func subscribeToNotifications(for portfolioId: String) -> AnyPublisher<CKSubscription, Error>
}

struct ActualCloudKitRepository: CloudKitRepository {
    
    let container: CKContainer = .default()
    
    var cancellables = Set<AnyCancellable>()
    
    func subscribeToNotifications(for portfolioId: String) -> AnyPublisher<CKSubscription, Error> {
        resultErrorCallbackPublisher { completion in
            let predicate = NSPredicate(format: "portfolio == %@", portfolioId)
            let subscription = CKQuerySubscription(recordType: "Notification",
                                                   predicate: predicate,
                                                   options: .firesOnRecordCreation)
            let notification = CKSubscription.NotificationInfo()
            notification.title = "Portfolio Alert"
            notification.alertBody = "Your portfolio needs a rebalance!"
            notification.soundName = "default"
            subscription.notificationInfo = notification
            CloudKitDatabase.pub.database(container).save(subscription, completionHandler: completion)
        }
    }
    
    func fetchCurrentUserID() -> AnyPublisher<CKRecord.ID, Error> {
        resultErrorCallbackPublisher { completion in
            container.fetchUserRecordID(completionHandler: completion)
        }
    }
    
    func fetchRecord(from database: CloudKitDatabase, withId id: CKRecord.ID) -> AnyPublisher<CKRecord, Error> {
        resultErrorCallbackPublisher({ completion in
            database.database(container).fetch(withRecordID: id, completionHandler: completion)
        })
    }
    
    func saveRecord(_ record: CKRecord, in database: CloudKitDatabase) -> AnyPublisher<CKRecord, Error> {
        resultErrorCallbackPublisher { completion in
            database.database(container).save(record, completionHandler: completion)
        }
    }
    
    func deleteRecord(_ record: CKRecord.ID, from database: CloudKitDatabase) -> AnyPublisher<CKRecord.ID, Error> {
        resultErrorCallbackPublisher { completion in
            database.database(container).delete(withRecordID: record, completionHandler: completion)
        }
    }
    
    func updateRecord(_ record: CKRecord, in database: CloudKitDatabase) -> AnyPublisher<CKRecord, Error> {
        resultErrorCallbackPublisher { completion in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success(_): completion(record, nil)
                case .failure(let error): completion(nil, error)
                }
            }
            database.database(container).add(operation)
        }
    }
    
    private func resultErrorCallbackPublisher<T>(_ f: @escaping (@escaping (T?, Error?) -> Void) -> Void) -> AnyPublisher<T, Error> {
        return Deferred { Future<T, Error> { promise in
            f { value, error in
                if let value = value {
                    promise(.success(value))
                } else if let error = error {
                    print(error.localizedDescription)
                    promise(.failure(error))
                }
            }
        }}
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
}

enum CloudKitDatabase {
    
    case priv, pub
    
    func database(_ container: CKContainer) -> CKDatabase {
        switch self {
        case .pub: return container.publicCloudDatabase
        case .priv: return container.privateCloudDatabase
        }
    }

}
