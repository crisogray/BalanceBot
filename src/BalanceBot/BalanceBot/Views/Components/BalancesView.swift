//
//  BalancesView.swift
//  BalanceBot
//
//  Created by Ben Gray on 09/03/2022.
//

import SwiftUI

struct BalancesView: View {
    
    @State var balanceList: BalanceList
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(balanceList.total.usdFormat).font(.largeTitle).padding(.vertical)
            let groupedBalances = balanceList.grouped(by: \.ticker)
            let sortedKeys = groupedBalances.sortedKeys
            ForEach(sortedKeys[0...2], id: \.self) { ticker in
                let balanceList = groupedBalances[ticker]!.sorted(\.balance)
                let first = balanceList.first!
                Text("\(ticker) - $\(balanceList.total) - $\(first.price)").padding(.top, 8)
                ForEach(balanceList, id: \.exchange) { balance in
                    Text("\t\(balance.exchange.rawValue): \(balance.balance)")
                }
            }
            Spacer()
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
 
