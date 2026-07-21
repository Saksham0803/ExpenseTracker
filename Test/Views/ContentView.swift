//
//  ContentView.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    @State private var showingAddExpense = false
    
    var body: some View {
        TabView {
            ExpenseListView()
                .tabItem {
                    Label("Expenses", systemImage: "list.bullet")
                }
            
            CreditCardView()
                .tabItem {
                    Label("Cards", systemImage: "creditcard.fill")
                }

            SummaryView()
                .tabItem {
                    Label("Summary", systemImage: "chart.pie.fill")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ExpenseManager())
}
