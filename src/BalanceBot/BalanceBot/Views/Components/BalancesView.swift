//
//  BalancesView.swift
//  BalanceBot
//
//  Created by Ben Gray on 09/03/2022.
//

import SwiftUI

struct BalancesView: View {
    
    @State var exchangeData: ExchangeData
    
    var body: some View {
        List {
            let total = exchangeData.balances.total(\.usdValue)
            Section(header: headerText(total.usdFormat)) {
                let groupedBalances = exchangeData.balances.grouped(by: \.ticker).filter { $0.value.total(\.usdValue) > 5 }
                let sortedKeys = groupedBalances.sortedKeys
                ForEach(sortedKeys, id: \.self) { ticker in
                    let balanceList = groupedBalances[ticker]!.sorted(\.balance)
                    balanceRow(ticker, total: total, balances: balanceList)
                }
            }
        }
    }
}

extension BalancesView {
    
    func headerText(_ string: String) -> some View {
        return Text(string)
            .font(.largeTitle.bold())
            .foregroundColor(.white)
            .padding(.vertical)
    }
    
    func balanceRow(_ ticker: String, total: Double, balances: BalanceList) -> some View {
        let balancesTotal = balances.total(\.usdValue)
        let percentage = 100 * balancesTotal / total
        return HStack(spacing: 0) {
            Text("\(ticker):")
                .font(.headline)
                .frame(width: 100, alignment: .leading)
            Spacer()
            Text("\(balances.total(\.usdValue).usdFormat)")
            Spacer()
            Text("\(percentage.percentageFormat)%")
                .font(.body.weight(.heavy))
                .frame(width: 80, alignment: .trailing)
        }.padding(.vertical, 4)
    }
    
}

