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
    // @State var qrInput = false
    // @State var key = ""
    // @State var secret = ""
        
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan \(exchange.rawValue) API Key QR Code").font(.headline)
            /*ZStack {
                Rectangle()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.init(.systemBackground))*/
                qrScanner
            //}
            //qrButton
            Spacer()
        }
        .padding()
        .navigationTitle(exchange.rawValue)
    }
    
}

extension APIKeyEntryView {
    
    /*
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
     */
    
    var qrScanner: some View {
        CodeScannerView(codeTypes: [.qr], showViewfinder: true) { response in
            guard case .success(let result) = response,
                  case .success(let (key, secret)) = exchange.parseAPIKeyQRString(result.string) else {
                      print("QR Error")
                      return
                  }
            injection.userSettingsInteractor.addAPIKey(key, secret: secret,
                                                       for: exchange, to: userSettings)
        }
        .aspectRatio(1, contentMode: .fit)
        .cornerRadius(12).clipped()
    }
    
    /*
    var qrButton: some View {
        Button {
            qrInput.toggle()
        } label: {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 32))
        }

    }
     */
    
}
