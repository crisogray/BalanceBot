//
//  APIKeyEntryView.swift
//  BalanceBot
//
//  Created by Ben Gray on 09/02/2022.
//

import SwiftUI
import CodeScanner

struct APIKeyEntryView: View {
        
    @Environment(\.injection) private var injection: Injection
    let exchange: Exchange
    @State var userSettings: UserSettings
    @State var isLoading = false
    @State var qrInput = false
    @State var key = ""
    @State var secret = ""
        
    var body: some View {
        Form {
            Section(header: headerTitle(exchange)){
                TextField("Key", text: $key)
                TextField("Secret", text: $secret)
            }
            if exchange.canQR {
                Section {
                        NavigationLink(isActive: $qrInput,
                                       destination: { scannerView },
                                       label: { qrButton })
                }
            }
            Section {
                HStack {
                    submitButton
                        .disabled(key.count < 10 || secret.count < 10)
                    if isLoading {
                        Spacer()
                        loadingView
                    }
                }
            }
        }
        .navigationTitle(exchange.rawValue)
    }
        
}

// MARK: Views

extension APIKeyEntryView {
    
    func headerTitle(_ exchange: Exchange) -> some View {
        Text("Paste \(exchange.rawValue) API Keys")
            .font(.headline)
    }
    
    var loadingView: some View {
        ProgressView().progressViewStyle(CircularProgressViewStyle())
    }
    
    var scannerView: some View {
        CodeScannerView(codeTypes: [.qr],
                        showViewfinder: true,
                        completion: codeScanHandler)
            .navigationTitle("Scan \(exchange.rawValue) QR")
            .navigationBarTitleDisplayMode(.inline)
    }
    
    var submitButton: some View {
        Button("Submit Keys", action: submit)
    }
    
    var qrButton: some View {
        HStack {
            Text("Scan QR Code")
            Spacer()
            Image(systemName: "qrcode.viewfinder")
        }
        
    }
    
}

// MARK: Functions

extension APIKeyEntryView {
    
    func codeScanHandler(_ response: Result<ScanResult, ScanError>) {
        guard case .success(let result) = response,
              case .success(let (key, secret)) = exchange.parseAPIKeyQRString(result.string) else {
                  print("QR Error")
                  return
              }
        self.key = key
        self.secret = secret
        qrInput = false
        submit()
    }
    
    func submit() {
        isLoading = true
        injection.userSettingsInteractor.addAPIKey(key, secret: secret,
                                                   for: exchange, to: userSettings)
    }
    
}
