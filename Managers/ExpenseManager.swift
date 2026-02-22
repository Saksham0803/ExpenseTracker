//
//  ExpenseManager.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import Foundation
import SwiftUI

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
        expenses.reduce(0) { $0 + $1.amount }
    }
    
    func expensesForCategory(_ category: ExpenseCategory) -> [Expense] {
        expenses.filter { $0.category == category }
    }
    
    func expensesForDateRange(start: Date, end: Date) -> [Expense] {
        expenses.filter { $0.date >= start && $0.date <= end }
    }
    
    func expensesForMonth(_ date: Date) -> [Expense] {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        return expensesForDateRange(start: startOfMonth, end: endOfMonth)
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
}
