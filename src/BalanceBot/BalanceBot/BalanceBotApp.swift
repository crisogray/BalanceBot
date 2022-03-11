//
//  BalanceBotApp.swift
//  BalanceBot
//
//  Created by Ben Gray on 02/02/2022.
//

import SwiftUI

let tintColor = Color(red: 244 / 255, green: 184 / 255, blue: 39 / 255)

@main
struct BalanceBotApp: App {
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(tintColor)
                .environment(\.injection, Injection.defaultValue)
                .preferredColorScheme(.dark)
        }
    }
}

let allowedTickers = ["BTC", "ETH", "USDT", "BNB", "USDC", "XRP", "LUNA", "ADA",
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
                      "FX", "SNT", "ARDR", "REQ", "PUNDIX", "CFX", "MDX", "RGT"]
