//
//  CloudKitHelpers.swift
//  BalanceBot
//
//  Created by Ben Gray on 04/02/2022.
//

import Foundation
import CloudKit

extension Account {
    static func fromCKRecord(_ record: CKRecord) -> Account {
        Account(id: record.recordID.recordName,
                portfolioId: record["portfolio_id"] as! String,
                connectedExchanges: record["connected_exchanges"] as! [String],
                excludedBalances: record["excluded_balances"] as! [String])
    }
    
    var ckRecord: CKRecord {
        let record = CKRecord(recordType: "Account", recordID: id.ckRecordId)
        record["portfolio_id"] = portfolioId
        record["connected_exchanges"] = connectedExchanges
        record["excluded_balances"] = excludedBalances
        return record
    }
    
}

extension Portfolio {
    static func fromCKRecord(_ record: CKRecord) -> Portfolio {
        let targetAllocationData = record["target_allocation"] as! String
        let balancesData = record["balances"] as! String
        return Portfolio(id: record.recordID.recordName,
                         strategy: record["strategy"] as! String,
                         targetAllocation: targetAllocationData.jsonDecode(type: [String : Float].self),
                         balances: balancesData.jsonDecode(type: [String : Float].self),
                         isLive: record["is_live"] as! Int)
    }
    
    var ckRecord: CKRecord {
        let record = CKRecord(recordType: "Account", recordID: id.ckRecordId)
        record["strategy"] = strategy
        record["target_allocation"] = targetAllocation.jsonString
        record["balances"] = balances.jsonString
        record["is_live"] = isLive
        return record
    }
    
}

extension Encodable {
    var jsonString: String {
        let encoder = JSONEncoder()
        return String(data: try! encoder.encode(self), encoding: .utf8)!
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
