//
//  ContentView.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    @StateObject private var notifications = NotificationManager.shared
    @State private var showingAddExpense = false
    /// One filter for Expenses and Summary, so Summary totals what Expenses lists.
    @State private var spendingFilter = PeriodFilter()

    var body: some View {
        TabView {
            ExpenseListView(filter: $spendingFilter)
                .tabItem {
                    Label("Expenses", systemImage: "list.bullet")
                }

            CreditCardView()
                .tabItem {
                    Label("Card", systemImage: "creditcard.fill")
                }

            CashUpiView()
                .tabItem {
                    Label("UPI & Cash", systemImage: "indianrupeesign.circle.fill")
                }

            TripsView()
                .tabItem {
                    Label("Trips", systemImage: "suitcase.fill")
                }

            SummaryView(filter: $spendingFilter)
                .tabItem {
                    Label("Summary", systemImage: "chart.pie.fill")
                }
        }
        .task { notifications.configure() }
        .sheet(isPresented: $notifications.showReviewInbox) {
            ReviewInboxView().environmentObject(expenseManager)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ExpenseManager())
}
