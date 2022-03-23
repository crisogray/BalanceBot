//
//  Exchange.swift
//  BalanceBot
//
//  Created by Ben Gray on 15/02/2022.
//

import Foundation
import Combine

// MARK: Definition

enum Exchange: String, CaseIterable {
    
    case bitfinex = "Bitfinex",
         ftx = "FTX",
         kraken = "Kraken",
         coinbase = "Coinbase"
    
    static var sortedAllCases: [Exchange] {
        allCases.sorted { $0.rawValue < $1.rawValue }
    }
    
}

// MARK: QR Reading

extension Exchange {
        
    var qrRegexPattern: String {
        switch self {
        case .bitfinex: return "-key:(.+)-secret:(.+)\\Z"
        case .kraken: return "key=(.+)&secret=(.+)\\Z"
        default: return ""
        }
    }
    
    func parseAPIKeyQRString(_ qr: String) -> Result<(String, String), Error> {
        do {
            let regex = try NSRegularExpression(pattern: qrRegexPattern, options: [])
            guard let match = regex.firstMatch(in: qr, options: [], range: NSRange(location: 0, length: qr.count)),
                  let keyRange = Range(match.range(at: 1), in: qr),
                  let secretRange = Range(match.range(at: 2), in: qr) else {
                      throw AppError.noRegexMatches
                  }
            return .success((String(qr[keyRange]), String(qr[secretRange])))
        } catch {
            return .failure(error)
        }
    }
    
}

// MARK: API Request

extension Exchange {
    
    var publicBaseURL: String {
        switch self {
        case .bitfinex: return "https://api-pub.bitfinex.com/v2/"
        case .kraken: return "https://api.kraken.com/0/"
        case .coinbase: return "https://api.coinbase.com/v2/"
        case .ftx: return "https://ftx.com/api/"
        }
    }
    
    var authenticatedBaseUrl: String {
        switch self {
        case .bitfinex: return "https://api.bitfinex.com/"
        default: return publicBaseURL
        }
    }
    
    var singlePriceRequest: Bool {
        switch self {
        case .ftx, .kraken, .coinbase: return true
        default: return false
        }
    }
    
    var balancesInOneStep: Bool {
        switch self {
        case .ftx: return true
        default: return false
        }
    }
    
    var canQR: Bool {
        qrRegexPattern != ""
    }
    
}

// MARK: API Response

extension Exchange {
    
    var priceTickerRegexPattern: String {
        switch self {
        case .bitfinex: return "^t(.+?):?(USD)?(BTC)?(ETH)?$"
        case .kraken: return "^X?(.+?)Z?USD\\Z"
        default: return "^(.+)\\Z"
        }
    }
    
    var balanceTickerRegexPattern: String {
        switch self {
        case .kraken: return "^[XZ]?(.+)$"
        default: return priceTickerRegexPattern
        }
    }
    
    var renames: [String : String] {
        switch self {
        case .kraken: return ["XBT" : "BTC"]
        default: return [:]
        }
    }
    
    func currency(from ticker: String, _ balance: Bool = false) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: balance ? balanceTickerRegexPattern : priceTickerRegexPattern, options: [])
            guard let match = regex.firstMatch(in: ticker, options: [],range: NSRange(location: 0, length: ticker.count)),
                  let currencyRange = Range(match.range(at: 1), in: ticker) else {
                      throw AppError.noRegexMatches
            }
            return String(ticker[currencyRange])
        } catch {
            return ticker
        }
    }
    
}

// MARK: Statics

extension Exchange {
    
    static let allowedTickers = ["BTC", "ETH", "USDT", "BNB", "USDC", "XRP", "LUNA", "ADA",
                                 "SOL", "AVAX", "BUSD", "DOT", "DOGE", "UST", "SHIB", "MATIC",
                                 "WBTC", "DAI", "CRO", "ATOM", "LTC", "NEAR", "LINK", "TRX",
                                 "UNI", "FTT", "LEO", "BCH", "ALGO", "MANA", "XLM", "BTCB",
                                 "HBAR", "ETC", "ICP", "EGLD", "SAND", "XMR", "FIL", "FTM",
                                 "VET", "KLAY", "THETA", "AXS", "WAVES", "XTZ", "HNT", "ZEC",
                                 "FLOW", "MIOTA", "RUNE", "EOS", "STX", "MKR", "BTT", "CAKE",
                                 "AAVE", "GRT", "GALA", "BSV", "TUSD", "ONE", "KCS", "NEO",
                                 "XEC", "HT", "QNT", "KDA", "NEXO", "CHZ", "ENJ", "CELO",
                                 "KSM", "AR", "OKB", "AMP", "DASH", "BAT", "USDP", "LRC",
                                 "ANC", "CRV", "CVX", "XEM", "TFUEL", "SCRT", "ROSE", "CEL",
                                 "XYM", "DCR", "BORA", "MINA", "HOT", "YFI", "COMP", "IOTX",
                                 "XDC", "PAXG", "SXP", "ANKR", "USDN", "RENBTC", "QTUM", "ICX",
                                 "BNT", "OMG", "RNDR", "GNO", "1INCH", "WAXP", "RVN", "BTG",
                                 "ZIL", "VLX", "LPT", "GT", "SNX", "KAVA", "GLM", "UMA",
                                 "ZEN", "RLY", "KNC", "GLMR", "WOO", "SC", "AUDIO", "NFT",
                                 "CHSB", "VGX", "ONT", "IMX", "FEI", "ZRX", "KEEP", "IOST",
                                 "REV", "ELON", "SKL", "STORJ", "SUSHI", "JST", "REN", "HIVE",
                                 "POLY", "UOS", "FLUX", "ILV", "BTRST", "CKB", "SYS", "NU",
                                 "DYDX", "GUSD", "DGB", "SPELL", "TEL", "PERP", "PEOPLE", "PLA",
                                 "YGG", "ENS", "OCEAN", "LSK", "XDB", "FXS", "XPRT", "FET",
                                 "WIN", "TRIBE", "MXC", "CSPR", "INJ", "SUPER", "SRM", "POWR",
                                 "TWT", "CELR", "DENT", "WRX", "XCH", "C98", "XNO", "CEEK",
                                 "XYO", "ONG", "PYR", "RAY", "MED", "COTI", "CHR", "ORBS",
                                 "FX", "SNT", "ARDR", "REQ", "PUNDIX", "CFX", "MDX", "RGT",
                                 "USD"]
    
}
