//
//  CloudKitHelpers.swift
//  BalanceBot
//
//  Created by Ben Gray on 04/02/2022.
//

import CloudKit
import Combine

extension Account {
    
    static func new(_ id: String) -> Account {
        Account(id: id, portfolioId: UUID().uuidString, connectedExchanges: [:], excludedBalances: [:])
    }
    
    static func fromCKRecord(_ record: CKRecord) -> Account {
        let connectedExchangesData = record["connected_exchanges"] as! String
        let excludedBalancesData = record["excluded_balances"] as! String
        return Account(id: record.recordID.recordName,
                portfolioId: record["portfolio_id"] as! String,
                connectedExchanges: connectedExchangesData.jsonDecode(type: [String : [String : String]].self),
                excludedBalances: excludedBalancesData.jsonDecode(type: [String : [String]].self))
    }
    
    var ckRecord: CKRecord {
        let record = CKRecord(recordType: "Account", recordID: id.ckRecordId)
        record["portfolio_id"] = portfolioId
        record["connected_exchanges"] = connectedExchanges.jsonString
        record["excluded_balances"] = excludedBalances.jsonString
        return record
    }
    
}

extension Portfolio {
    
    static func new(_ id: String) -> Portfolio {
        Portfolio(id: id, rebalanceTrigger: .calendar(.monthly), targetAllocation: [:],
                  balances: [:], assetGroups: [:], isLive: 0)
    }
    
    static func fromCKRecord(_ record: CKRecord) -> Portfolio {
        let targetAllocationData = record["target_allocation"] as! String
        let balancesData = record["balances"] as! String
        let assetGroupsData = record["asset_groups"] as! String
        return Portfolio(id: record.recordID.recordName,
                         rebalanceTrigger: RebalanceTrigger(record["rebalance_trigger"] as! String),
                         targetAllocation: targetAllocationData.jsonDecode(type: [String : Double].self),
                         balances: balancesData.jsonDecode(type: [String : Double].self),
                         assetGroups: assetGroupsData.jsonDecode(type: [String : [String]].self),
                         isLive: record["is_live"] as! Int)
    }
    
    var ckRecord: CKRecord {
        let record = CKRecord(recordType: "Portfolio", recordID: id.ckRecordId)
        record["rebalance_trigger"] = rebalanceTrigger.storedString
        record["target_allocation"] = targetAllocation.jsonString
        record["balances"] = balances.jsonString
        record["asset_groups"] = assetGroups.jsonString
        record["is_live"] = isLive
        return record
    }
    
}

extension Publisher where Output == ((CKRecord, CKRecord), Bool) {
    
    func sinkToUserSettings(_ sendUserSettings: @escaping (Loadable<UserSettings>) -> Void) -> AnyCancellable {
        return sink { completion in
            guard case .failure(let error) = completion else { return }
            sendUserSettings(.failed(error))
        } receiveValue: { value in
            sendUserSettings(.loaded(UserSettings(account: Account.fromCKRecord(value.0.0),
                                                  portfolio: Portfolio.fromCKRecord(value.0.1),
                                                  hasNotifications: value.1)))
        }
    }
    
}

extension Encodable {
    var jsonString: String {
        return String(data: jsonData, encoding: .utf8)!
    }
    
    var jsonData: Data {
        return try! JSONEncoder().encode(self)
    }
}

extension String {
    func jsonDecode<T: Decodable>(type: T.Type) -> T {
        let decoder = JSONDecoder()
        return try! decoder.decode(type.self, from: data(using: .utf8)!)
    }
}

import CryptoKit

extension String {
    var ckRecordId: CKRecord.ID {
        CKRecord.ID(recordName: self)
    }
    
    var md5: String {
        let digest = Insecure.MD5.hash(data: data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
