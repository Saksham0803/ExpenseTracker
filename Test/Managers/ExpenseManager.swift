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
    @Published var groups: [PersonGroup] = []

    /// Day of month the credit-card statement closes (e.g. 20 → cycle runs the
    /// 20th of one month up to the 20th of the next). Persisted.
    @Published var billingCycleDay: Int = 20 {
        didSet {
            let clamped = min(max(billingCycleDay, 1), 28)
            if clamped != billingCycleDay { billingCycleDay = clamped; return }
            UserDefaults.standard.set(billingCycleDay, forKey: billingDayKey)
        }
    }

    private let expensesKey = "SavedExpenses"
    private let groupsKey = "SavedGroups"
    private let billingDayKey = "BillingCycleDay"

    // Shared instance for App Intents
    static let shared = ExpenseManager()

    init() {
        loadExpenses()
        loadGroups()
        if let saved = UserDefaults.standard.object(forKey: billingDayKey) as? Int {
            billingCycleDay = saved
        }
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

    // MARK: - Credit Card Split Tracking

    /// All expenses that were split on the credit card, newest first.
    var creditCardExpenses: [Expense] {
        expenses.filter { $0.isCreditCardSplit }.sorted { $0.date > $1.date }
    }

    /// Total amount charged to the card across all split payments.
    var creditCardCharged: Double {
        creditCardExpenses.reduce(0) { $0 + ($1.split?.totalAmount ?? 0) }
    }

    /// Your own net spend from card splits (your shares only).
    var creditCardMyNet: Double {
        creditCardExpenses.reduce(0) { $0 + ($1.split?.myShare ?? 0) }
    }

    /// Money still owed to you across all card splits.
    var creditCardOutstanding: Double {
        creditCardExpenses.reduce(0) { $0 + ($1.split?.outstandingTotal ?? 0) }
    }

    /// Money already recovered from others.
    var creditCardRecovered: Double {
        creditCardExpenses.reduce(0) { $0 + ($1.split?.settledTotal ?? 0) }
    }

    // MARK: - Billing Cycles

    /// A statement period running from `start` (inclusive) to `end` (exclusive),
    /// both landing on the configured billing day.
    struct BillingCycle: Identifiable, Hashable {
        let start: Date
        let end: Date
        var id: Date { start }
    }

    /// The billing cycle that contains `date`, based on `billingCycleDay`.
    func cycle(containing date: Date) -> BillingCycle {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        let day = min(max(billingCycleDay, 1), 28)

        let startOfDay = cal.startOfDay(for: date)
        let currentDay = cal.component(.day, from: startOfDay)

        // Anchor to this month's billing day, then step back if we're before it.
        var comps = cal.dateComponents([.year, .month], from: startOfDay)
        comps.day = day
        let thisMonthAnchor = cal.date(from: comps) ?? startOfDay
        let start = currentDay >= day
            ? thisMonthAnchor
            : cal.date(byAdding: .month, value: -1, to: thisMonthAnchor) ?? thisMonthAnchor
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return BillingCycle(start: start, end: end)
    }

    /// The cycle one period before/after the given one.
    func cycle(offsetting cycle: BillingCycle, by months: Int) -> BillingCycle {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        let ref = cal.date(byAdding: .month, value: months, to: cycle.start) ?? cycle.start
        return self.cycle(containing: ref)
    }

    /// Credit-card payments whose date falls in the given cycle, newest first.
    func creditCardExpenses(in cycle: BillingCycle) -> [Expense] {
        creditCardExpenses.filter { $0.date >= cycle.start && $0.date < cycle.end }
    }

    func charged(in cycle: BillingCycle) -> Double {
        creditCardExpenses(in: cycle).reduce(0) { $0 + ($1.split?.totalAmount ?? 0) }
    }
    func myNet(in cycle: BillingCycle) -> Double {
        creditCardExpenses(in: cycle).reduce(0) { $0 + ($1.split?.myShare ?? 0) }
    }
    func outstanding(in cycle: BillingCycle) -> Double {
        creditCardExpenses(in: cycle).reduce(0) { $0 + ($1.split?.outstandingTotal ?? 0) }
    }
    func recovered(in cycle: BillingCycle) -> Double {
        creditCardExpenses(in: cycle).reduce(0) { $0 + ($1.split?.settledTotal ?? 0) }
    }

    /// Toggle a single participant's settled state and persist.
    func setSettled(_ settled: Bool, participantID: UUID, in expense: Expense) {
        guard let eIndex = expenses.firstIndex(where: { $0.id == expense.id }),
              var split = expenses[eIndex].split,
              let pIndex = split.participants.firstIndex(where: { $0.id == participantID })
        else { return }

        split.participants[pIndex].isSettled = settled
        expenses[eIndex].split = split
        saveExpenses()
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

    // MARK: - Saved Groups

    func addGroup(_ group: PersonGroup) {
        groups.append(group)
        saveGroups()
    }

    func updateGroup(_ group: PersonGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
            saveGroups()
        }
    }

    func deleteGroup(_ group: PersonGroup) {
        groups.removeAll { $0.id == group.id }
        saveGroups()
    }

    func deleteGroups(at offsets: IndexSet) {
        groups.remove(atOffsets: offsets)
        saveGroups()
    }

    private func saveGroups() {
        if let encoded = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(encoded, forKey: groupsKey)
        }
    }

    private func loadGroups() {
        if let data = UserDefaults.standard.data(forKey: groupsKey),
           let decoded = try? JSONDecoder().decode([PersonGroup].self, from: data) {
            groups = decoded
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
