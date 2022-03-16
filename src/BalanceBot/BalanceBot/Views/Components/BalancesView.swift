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
                Text(exchangeData.balances.total(\.usdValue).usdFormat)
                    .font(.largeTitle).padding(.vertical)
                let groupedBalances = exchangeData.balances.grouped(by: \.ticker)
                let sortedKeys = groupedBalances.sortedKeys
                ForEach(sortedKeys, id: \.self) { ticker in
                    let balanceList = groupedBalances[ticker]!.sorted(\.balance)
                    Text("\(ticker) - \(balanceList.total(\.usdValue).usdFormat)")
                        .padding(.top, 0)
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
 
