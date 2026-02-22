//
//  ExpenseManager.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import Foundation
import SwiftUI
import Combine


class ExpenseManager: ObservableObject {
    @Published var expenses: [Expense] = []
    
    private let expensesKey = "SavedExpenses"
    
    // Shared instance for App Intents
    static let shared = ExpenseManager()
    
    init() {
        loadExpenses()
    }
    
    func addExpense(_ expense: Expense) {
        expenses.append(expense)
        saveExpenses()
    }
    
    func updateExpense(_ expense: Expense) {
        if let index = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[index] = expense
            saveExpenses()
        }
    }
    
    func deleteExpense(_ expense: Expense) {
        expenses.removeAll { $0.id == expense.id }
        saveExpenses()
    }
    
    func deleteExpense(at offsets: IndexSet) {
        expenses.remove(atOffsets: offsets)
        saveExpenses()
    }
    
    var totalExpenses: Double {
        expenses.reduce(0) { $0 + $1.displayAmount }
    }
    
    var totalSpent: Double {
        expenses.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
    
    var totalRefunded: Double {
        expenses.filter { $0.type == .refund }.reduce(0) { $0 + $1.amount }
    }
    
    func expensesForCategory(_ category: ExpenseCategory) -> [Expense] {
        expenses.filter { $0.category == category }
    }
    
    func expensesForDateRange(start: Date, end: Date) -> [Expense] {
        expenses.filter { $0.date >= start && $0.date <= end }
    }
    
    func expensesForMonth(_ date: Date) -> [Expense] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        
        return expenses.filter { expense in
            let expenseComponents = calendar.dateComponents([.year, .month], from: expense.date)
            return expenseComponents.year == components.year && 
                   expenseComponents.month == components.month
        }
    }
    
    private func saveExpenses() {
        if let encoded = try? JSONEncoder().encode(expenses) {
            UserDefaults.standard.set(encoded, forKey: expensesKey)
        }
    }
    
    private func loadExpenses() {
        if let data = UserDefaults.standard.data(forKey: expensesKey),
           let decoded = try? JSONDecoder().decode([Expense].self, from: data) {
            expenses = decoded
        }
    }
    
    // MARK: - Export/Import Functions
    
    /// Export expenses as JSON data
    func exportExpenses() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(expenses)
    }
    
    /// Import expenses from JSON data
    func importExpenses(from data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let importedExpenses = try? decoder.decode([Expense].self, from: data) {
            // Merge with existing expenses (avoid duplicates by ID)
            let existingIDs = Set(expenses.map { $0.id })
            let newExpenses = importedExpenses.filter { !existingIDs.contains($0.id) }
            
            if !newExpenses.isEmpty {
                expenses.append(contentsOf: newExpenses)
                saveExpenses()
                return true
            } else if importedExpenses.isEmpty {
                // Allow importing empty array to clear data
                return false
            } else {
                // All expenses already exist
                return false
            }
        }
        return false
    }
    
    /// Replace all expenses with imported data
    func replaceExpenses(with data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let importedExpenses = try? decoder.decode([Expense].self, from: data) {
            expenses = importedExpenses
            saveExpenses()
            return true
        }
        return false
    }
    
    /// Get export file name with timestamp
    func getExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "ExpenseTracker_Backup_\(timestamp).json"
    }
}
