//
//  UserPermissionsInteractor.swift
//  CountriesSwiftUI
//
//  Created by Alexey Naumov on 26.04.2020.
//  Copyright © 2020 Alexey Naumov. All rights reserved.
//

import Foundation
import UserNotifications
import UIKit

enum Permission {
    case pushNotifications
}

extension Permission {
    enum Status: Equatable {
        case unknown
        case notRequested
        case granted
        case denied
    }
}

protocol UserPermissionsInteractor {
    func fetchPushNotificationsPermissionStatus()
    func requestPushNotificationsPermission()
}

// MARK: - ActualUserPermissionsInteractor

struct ActualUserPermissionsInteractor: UserPermissionsInteractor {
    
    let appState: Store<AppState>
    
    init(appState: Store<AppState>) {
        self.appState = appState
    }
    
    func fetchPushNotificationsPermissionStatus() {
        print("Here")
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                appState[\.permissions.push] = settings.authorizationStatus.map
            }
        }
    }
    
    func requestPushNotificationsPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { (isGranted, error) in
            DispatchQueue.main.async {
                if isGranted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                appState[\.permissions.push] = isGranted ? .granted : .denied
            }
        }
    }
}
    
// MARK: - Push Notifications

extension UNAuthorizationStatus {
    var map: Permission.Status {
        switch self {
        case .denied: return .denied
        case .authorized: return .granted
        case .notDetermined, .provisional, .ephemeral: return .notRequested
        @unknown default: return .notRequested
        }
    }
}
