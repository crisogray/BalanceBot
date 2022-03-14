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
        ScrollView(.vertical) {
            VStack(alignment: .leading) {
                Text(exchangeData.balances.total(\.usdValue).usdFormat).font(.largeTitle).padding(.vertical)
                let groupedBalances = exchangeData.balances.grouped(by: \.ticker)
                let sortedKeys = groupedBalances.sortedKeys
                ForEach(sortedKeys, id: \.self) { ticker in
                    let balanceList = groupedBalances[ticker]!.sorted(\.balance)
                    let first = balanceList.first!
                    Text("\(ticker) - \(balanceList.total(\.usdValue).usdFormat) - \(first.price.usdFormat)").padding(.top, 0)
                    ForEach(balanceList, id: \.exchange) { balance in
                        Text("\t\(balance.exchange.rawValue): \(balance.balance)")
                    }
                }
                Spacer()
            }
        }
    }
}

/*
struct BalancesView_Previews: PreviewProvider {
    static var previews: some View {
        BalancesView()
    }
}
*/
 
