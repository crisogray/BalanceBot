//
//  KeychainRepository.swift
//  BalanceBot
//
//  Created by Ben Gray on 03/02/2022.
//

import Foundation
import Security

protocol KeychainRepository {
    func saveItem(_ item: Data, withKey key: String) -> Bool
    func itemExists(for key: String) -> Bool
    func getItem(for key: String) -> Data?
    func deleteItem(for key: String) -> Bool
}

struct ActualKeychainRepository: KeychainRepository {
    
    func saveItem(_ item: Data, withKey key: String) -> Bool {
        return SecItemAdd(attributes(for: key, data: item), nil) == errSecSuccess
    }
    
    func attributes(for key: String, data: Data) -> CFDictionary {
        var attributes = query(for: key)
        attributes[kSecValueData as String] = data
        return attributes as CFDictionary
    }
    
    func query(for key: String) -> [String : Any] {
        [kSecClass as String : kSecClassInternetPassword, kSecAttrAccount as String : key]
    }
    
    func itemExists(for key: String) -> Bool {
        SecItemCopyMatching(query(for: key) as CFDictionary, nil) == errSecSuccess
    }
    
    func getItem(for key: String) -> Data? {
        var item: AnyObject? = nil
        SecItemCopyMatching(query(for: key) as CFDictionary, &item)
        return item as? Data
    }
    
    func deleteItem(for key: String) -> Bool {
        SecItemDelete(query(for: key) as CFDictionary) == errSecSuccess
    }
    
}
