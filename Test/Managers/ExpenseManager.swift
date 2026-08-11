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
    @Published var trips: [Trip] = []

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
    private let tripsKey = "SavedTrips"

    // Shared instance for App Intents
    static let shared = ExpenseManager()

    init() {
        loadExpenses()
        loadGroups()
        loadTrips()
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
    
    /// Stored expenses plus derived rows for your share of trip expenses. This is
    /// the basis for personal totals and the Expenses/Summary views so your trip
    /// contribution counts as spending — without ever being stored twice.
    /// Zero-contribution rows (e.g. a payment you fronted entirely for others) are
    /// excluded here — they still appear in full in the Card / UPI & Cash tabs.
    var allExpenses: [Expense] {
        (expenses + myTripContributions).filter { $0.amount > 0 }
    }

    var totalExpenses: Double {
        allExpenses.reduce(0) { $0 + $1.displayAmount }
    }

    var totalSpent: Double {
        allExpenses.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    var totalRefunded: Double {
        allExpenses.filter { $0.type == .refund }.reduce(0) { $0 + $1.amount }
    }

    func expensesForCategory(_ category: ExpenseCategory) -> [Expense] {
        allExpenses.filter { $0.category == category }
    }

    // MARK: - Payment-method Tracking

    /// Every split expense, newest first (used for importing into trips).
    var splitExpenses: [Expense] {
        expenses.filter { $0.isSplit }.sorted { $0.date > $1.date }
    }

    /// Split expenses restricted to the given payment methods, newest first.
    func splitExpenses(methods: Set<PaymentMethod>) -> [Expense] {
        splitExpenses.filter { methods.contains($0.method) }
    }

    /// ALL expenses (split or not) paid via the given methods, newest first.
    /// The Card and UPI & Cash tabs show every transaction in full, not just splits.
    func expensesPaid(via methods: Set<PaymentMethod>) -> [Expense] {
        expenses.filter { methods.contains($0.method) }.sorted { $0.date > $1.date }
    }

    // Aggregate helpers over a list. Non-split expenses are entirely your own, so
    // their full amount counts as both the total and your share.
    func chargedTotal(_ list: [Expense]) -> Double { list.reduce(0) { $0 + ($1.split?.totalAmount ?? $1.amount) } }
    func myNetTotal(_ list: [Expense]) -> Double { list.reduce(0) { $0 + ($1.split?.myShare ?? $1.amount) } }
    func outstandingTotal(_ list: [Expense]) -> Double { list.reduce(0) { $0 + ($1.split?.outstandingTotal ?? 0) } }
    func recoveredTotal(_ list: [Expense]) -> Double { list.reduce(0) { $0 + ($1.split?.settledTotal ?? 0) } }

    // MARK: Card-only (for the Card tab + billing cycles)

    /// Every card transaction (split or not), newest first.
    var creditCardExpenses: [Expense] {
        expensesPaid(via: [.card])
    }

    var creditCardCharged: Double { chargedTotal(creditCardExpenses) }
    var creditCardMyNet: Double { myNetTotal(creditCardExpenses) }
    var creditCardOutstanding: Double { outstandingTotal(creditCardExpenses) }
    var creditCardRecovered: Double { recoveredTotal(creditCardExpenses) }

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

    func charged(in cycle: BillingCycle) -> Double { chargedTotal(creditCardExpenses(in: cycle)) }
    func myNet(in cycle: BillingCycle) -> Double { myNetTotal(creditCardExpenses(in: cycle)) }
    func outstanding(in cycle: BillingCycle) -> Double { outstandingTotal(creditCardExpenses(in: cycle)) }
    func recovered(in cycle: BillingCycle) -> Double { recoveredTotal(creditCardExpenses(in: cycle)) }

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
        allExpenses.filter { $0.date >= start && $0.date <= end }
    }

    func expensesForMonth(_ date: Date) -> [Expense] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)

        return allExpenses.filter { expense in
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

    // MARK: - Trips

    func addTrip(_ trip: Trip) {
        trips.append(trip)
        saveTrips()
    }

    func updateTrip(_ trip: Trip) {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[index] = trip
            saveTrips()
        }
    }

    func deleteTrip(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        saveTrips()
    }

    /// Add/update/remove a single expense inside a trip and persist.
    func upsertTripExpense(_ expense: TripExpense, in tripID: UUID) {
        guard let ti = trips.firstIndex(where: { $0.id == tripID }) else { return }
        if let ei = trips[ti].expenses.firstIndex(where: { $0.id == expense.id }) {
            trips[ti].expenses[ei] = expense
        } else {
            trips[ti].expenses.append(expense)
        }
        saveTrips()
    }

    func deleteTripExpense(_ expenseID: UUID, in tripID: UUID) {
        guard let ti = trips.firstIndex(where: { $0.id == tripID }) else { return }
        trips[ti].expenses.removeAll { $0.id == expenseID }
        saveTrips()
    }

    /// Derived personal rows for your share of every trip expense. These are not
    /// stored — they are recomputed from trips, so trip data is never duplicated.
    var myTripContributions: [Expense] {
        trips.flatMap { trip -> [Expense] in
            guard let me = trip.myMember else { return [] }
            return trip.expenses.compactMap { te in
                let myShare = te.share(of: me.id)
                guard myShare > 0 else { return nil }
                return Expense(
                    id: te.id,
                    title: "\(trip.name) · \(te.title)",
                    amount: myShare,
                    category: te.category,
                    type: .expense,
                    date: te.date,
                    notes: te.notes,
                    split: nil,
                    paymentMethod: nil,
                    tripRef: TripExpenseRef(tripID: trip.id, tripName: trip.name)
                )
            }
        }
    }

    private func saveTrips() {
        if let encoded = try? JSONEncoder().encode(trips) {
            UserDefaults.standard.set(encoded, forKey: tripsKey)
        }
    }

    private func loadTrips() {
        if let data = UserDefaults.standard.data(forKey: tripsKey),
           let decoded = try? JSONDecoder().decode([Trip].self, from: data) {
            trips = decoded
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
