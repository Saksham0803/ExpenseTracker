//
//  ExpenseTrackerApp.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import SwiftUI
import Combine

@main
struct ExpenseTrackerApp: App {
    @StateObject private var expenseManager = ExpenseManager.shared
    @State private var sharedMessage: String?
    @State private var showingMessageImport = false
    
    init() {
        // Ensure shared instance is initialized
        _ = ExpenseManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(expenseManager)
                .onOpenURL { url in
                    handleSharedURL(url)
                }
                .sheet(isPresented: $showingMessageImport) {
                    MessageImportView(initialMessage: sharedMessage ?? "")
                }
        }
    }
    
    private func handleSharedURL(_ url: URL) {
        // Handle shared text/messages via URL scheme
        if url.scheme == "expensetracker" {
            // Handle expense data from shortcuts
            if let title = url.queryItems?["title"],
               let amountString = url.queryItems?["amount"],
               let amount = Double(amountString) {
                let categoryString = url.queryItems?["category"] ?? "other"
                let category = ExpenseCategory(rawValue: categoryString.capitalized) ?? .other
                let notes = url.queryItems?["notes"] ?? ""
                
                let typeString = url.queryItems?["type"] ?? "expense"
                let type = ExpenseType(rawValue: typeString.capitalized) ?? .expense
                
                // Convert date to IST timezone
                let istTimeZone = TimeZone(identifier: "Asia/Kolkata")!
                let calendar = Calendar.current
                let components = calendar.dateComponents(in: istTimeZone, from: Date())
                let istDate = calendar.date(from: components) ?? Date()
                
                let expense = Expense(
                    title: title,
                    amount: amount,
                    category: category,
                    type: type,
                    date: istDate,
                    notes: notes
                )
                
                ExpenseManager.shared.addExpense(expense)
            } else if let message = url.queryItems?["message"] {
                sharedMessage = message
                showingMessageImport = true
            }
        }
    }
}

extension URL {
    var queryItems: [String: String]? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        
        var items: [String: String] = [:]
        for item in queryItems {
            items[item.name] = item.value
        }
        return items
    }
}
