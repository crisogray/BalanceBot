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
        VStack(alignment: .leading, spacing: 12) {
            Text(qrInput ? "Scan \(exchange.rawValue) API Key QR Code"
                 : "Paste \(exchange.rawValue) API Keys").font(.headline)
            ZStack {
                Rectangle()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.init(.systemBackground))
                if qrInput {
                    scannerView
                } else {
                    stringInputs
                }
            }
            if key.count > 10 && secret.count > 10 && !isLoading {
                submitButton
            } else if isLoading {
                HStack {
                    Text("Loading API Key").padding(.trailing)
                    ProgressView().progressViewStyle(CircularProgressViewStyle())
                }
            } else if exchange.canQR {
                qrButton
            }
            Spacer()
        }
        .padding()
        .navigationTitle(exchange.rawValue)
    }
    
}

extension APIKeyEntryView {
    
    var stringInputs: some View {
        VStack {
            input($key, label: "Key", placeholder: "\(exchange.rawValue) API Key")
                .padding(.bottom)
            input($secret, label: "Secret", placeholder: "\(exchange.rawValue) API Key Secret")
        }.padding()
    }
    
    func input(_ binding: Binding<String>, label: String, placeholder: String?) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.headline)
            TextField(placeholder ?? label, text: binding)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
    
    var scannerView: some View {
        CodeScannerView(codeTypes: [.qr], showViewfinder: true, completion: codeScanHandler)
            .aspectRatio(1, contentMode: .fit)
            .cornerRadius(12).clipped()
    }
    
    func codeScanHandler(_ response: Result<ScanResult, ScanError>) {
        guard case .success(let result) = response,
              case .success(let (key, secret)) = exchange.parseAPIKeyQRString(result.string) else {
                  print("QR Error")
                  return
              }
        self.key = key
        self.secret = secret
        qrInput = false
    }
    
    func submit() {
        isLoading = true
        injection.userSettingsInteractor.addAPIKey(key, secret: secret,
                                                   for: exchange, to: userSettings)
    }
    
    var submitButton: some View {
        Button("Submit Keys", action: submit)
    }
    
    var qrButton: some View {
        Button {
            qrInput.toggle()
        } label: {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 32))
        }

    }
    
}
