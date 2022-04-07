//
//  Rebalance.swift
//  BalanceBot
//
//  Created by Ben Gray on 24/03/2022.
//

import SwiftUI

struct Rebalance: View {
    
    @State var instructions: [Instruction]
    @Binding var isDisplayed: Bool
    
    var body: some View {
        NavigationView {
            List {
                ForEach(instructions, id: \.self) { instruction in
                    instructionRow(instruction)
                }
            }
            .listStyle(PlainListStyle())
            .navigationTitle("To Rebalance")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Close") { isDisplayed = false }
                }
            }
        }
        
    }
    
}

extension Rebalance {
    
    func instructionRow(_ instruction: Instruction) -> some View {
        let send = instruction.command == .send
        return HStack {
            Text("\(instruction.command.rawValue.uppercased())")
                .frame(width: 80, alignment: .leading)
                .font(.title.bold())
                .padding(.vertical)
            Spacer()
            VStack(alignment: .leading) {
                Text(instruction.usdValue.usdFormat).font(.title2.bold())
                Text(send ? "to \(instruction.exchange2!.rawValue)" : "worth of \(instruction.asset)")
                    .font(.subheadline)
            }
            Spacer()
            Spacer()
            Text((send ? "from " : "on ") + instruction.exchange.rawValue)
                .frame(width: 100, alignment: .leading)
        }
    }
    
}
