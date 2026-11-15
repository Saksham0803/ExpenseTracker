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
    /// Credits ("money received") waiting to be matched to someone's share.
    @Published var receivedPayments: [ReceivedPayment] = []

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
    private let receivedKey = "ReceivedPayments"

    // Shared instance for App Intents
    static let shared = ExpenseManager()

    init() {
        loadExpenses()
        loadGroups()
        loadTrips()
        loadReceivedPayments()
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
            syncTripExpenses(from: expense)
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
    /// Zero-contribution rows (e.g. a payment you fronted entirely for others) and
    /// money sent that isn't your spending (e.g. to family) are excluded here —
    /// they still appear in full in the Card / UPI & Cash tabs.
    var allExpenses: [Expense] {
        (expenses + myTripContributions).filter { $0.amount > 0 && !$0.isTransfer }
    }

    /// Accounts / cards (last 4 digits) seen in a list, for the account filter.
    func accounts(in list: [Expense]) -> [String] {
        Array(Set(list.compactMap(\.account))).sorted()
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

    // MARK: - Review Inbox (auto-captured transactions)

    /// Auto-captured transactions still needing a note/category, newest first.
    var needsReviewExpenses: [Expense] {
        expenses.filter { $0.requiresReview }.sorted { $0.date > $1.date }
    }

    /// Everything waiting in the review inbox: notes to add + money to match.
    var needsReviewCount: Int { needsReviewExpenses.count + receivedPayments.count }

    /// Clear the review flag once the user has annotated the transaction.
    func markReviewed(_ id: UUID) {
        guard let i = expenses.firstIndex(where: { $0.id == id }) else { return }
        expenses[i].needsReview = false
        saveExpenses()
    }

    // MARK: - Money Received (credits)

    func addReceivedPayment(_ payment: ReceivedPayment) {
        receivedPayments.append(payment)
        saveReceivedPayments()
    }

    /// Open shares someone still owes you, best matches first: name and amount,
    /// then name only, then amount only, then the rest (newest payment first).
    func matches(for payment: ReceivedPayment) -> [ShareMatch] {
        let senderTokens = Self.nameTokens(payment.sender)
        let senderText = payment.sender.lowercased()
        var result: [ShareMatch] = []
        for expense in splitExpenses {
            guard let split = expense.split else { continue }
            for p in split.participants where p.remaining > 0.009 {
                let personTokens = Self.nameTokens(p.name)
                let nameMatches = personTokens.contains { senderText.contains($0) }
                    || senderTokens.contains { p.name.lowercased().contains($0) }
                result.append(ShareMatch(
                    expenseID: expense.id,
                    participantID: p.id,
                    personName: p.name,
                    expenseTitle: expense.title,
                    remaining: p.remaining,
                    nameMatches: nameMatches,
                    amountMatches: abs(p.remaining - payment.amount) < 0.01
                ))
            }
        }
        func rank(_ m: ShareMatch) -> Int { (m.nameMatches ? 2 : 0) + (m.amountMatches ? 1 : 0) }
        return result.enumerated()
            .sorted { rank($0.element) != rank($1.element) ? rank($0.element) > rank($1.element) : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Apply a received payment to one share. A partial amount leaves the rest
    /// owing; anything left over stays in the inbox to apply to another share.
    func apply(_ paymentID: UUID, to participantID: UUID, in expenseID: UUID) {
        guard let pi = receivedPayments.firstIndex(where: { $0.id == paymentID }),
              let ei = expenses.firstIndex(where: { $0.id == expenseID }),
              var split = expenses[ei].split,
              let si = split.participants.firstIndex(where: { $0.id == participantID }) else { return }

        let applied = min(receivedPayments[pi].amount, split.participants[si].remaining)
        guard applied > 0 else { return }
        split.participants[si].paidBack = split.participants[si].received + applied
        if split.participants[si].remaining < 0.01 { split.participants[si].isSettled = true }
        expenses[ei].split = split
        saveExpenses()

        receivedPayments[pi].amount -= applied
        if receivedPayments[pi].amount < 0.01 { receivedPayments.remove(at: pi) }
        saveReceivedPayments()
    }

    /// Treat an unmatched credit as a merchant refund (reduces your spending).
    func markAsRefund(_ paymentID: UUID) {
        guard let pi = receivedPayments.firstIndex(where: { $0.id == paymentID }) else { return }
        let payment = receivedPayments.remove(at: pi)
        saveReceivedPayments()
        // Land the refund in the tab it was paid back to (e.g. "credited to your card").
        let method = payment.method ?? TransactionParser().parseMessage(payment.rawMessage)?.method
        addExpense(Expense(title: payment.sender, amount: payment.amount, category: .other,
                           type: .refund, date: payment.date, notes: "", paymentMethod: method,
                           account: payment.account))
    }

    /// Drop a credit that isn't spending-related (salary, family transfer, …).
    func dismissReceivedPayment(_ paymentID: UUID) {
        receivedPayments.removeAll { $0.id == paymentID }
        saveReceivedPayments()
    }

    /// Lower-cased name words of 3+ letters, for loose name matching.
    private static func nameTokens(_ name: String) -> [String] {
        name.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 }
    }

    private func saveReceivedPayments() {
        if let encoded = try? JSONEncoder().encode(receivedPayments) {
            UserDefaults.standard.set(encoded, forKey: receivedKey)
        }
    }

    private func loadReceivedPayments() {
        if let data = UserDefaults.standard.data(forKey: receivedKey),
           let decoded = try? JSONDecoder().decode([ReceivedPayment].self, from: data) {
            receivedPayments = decoded
        }
    }

    // MARK: - Statement Import

    private let importedRowsKey = "ImportedStatementRows"

    /// Flag rows that are already in the app — imported from a statement before,
    /// or matching an existing transaction on the same day for the same amount
    /// (e.g. auto-captured from SMS). Flagged rows start unticked.
    func markDuplicates(_ rows: inout [StatementRow]) {
        let imported = Set(UserDefaults.standard.stringArray(forKey: importedRowsKey) ?? [])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        // Existing (day, amount) pairs; each can only absorb one statement row.
        var debits = expenses.filter { $0.type == .expense }
            .map { (calendar.startOfDay(for: $0.date), $0.split?.totalAmount ?? $0.amount) }
        var credits = expenses.filter { $0.type == .refund }.map { (calendar.startOfDay(for: $0.date), $0.amount) }
            + receivedPayments.map { (calendar.startOfDay(for: $0.date), $0.amount) }

        for i in rows.indices {
            let day = calendar.startOfDay(for: rows[i].date)
            let sameTxn: ((Date, Double)) -> Bool = { $0.0 == day && abs($0.1 - rows[i].amount) < 0.01 }
            var duplicate = imported.contains(rows[i].fingerprint)
            if !duplicate {
                if rows[i].isCredit, let j = credits.firstIndex(where: sameTxn) {
                    credits.remove(at: j); duplicate = true
                } else if !rows[i].isCredit, let j = debits.firstIndex(where: sameTxn) {
                    debits.remove(at: j); duplicate = true
                }
            }
            if duplicate {
                rows[i].flag = .duplicate
                rows[i].include = false
            }
        }
    }

    /// Log statement rows in one save: spends become expenses, credits wait in
    /// Money received. Returns the created expenses (for the split editor).
    @discardableResult
    func importStatementRows(_ rows: [StatementRow]) -> [Expense] {
        var created: [Expense] = []
        for row in rows {
            if row.isCredit {
                receivedPayments.append(ReceivedPayment(amount: row.amount, sender: row.merchant, date: row.date,
                                                        rawMessage: row.description, method: row.method,
                                                        account: row.account))
            } else {
                // Money to your own accounts or to family shows in the method tab, not as spending.
                let transfer = row.notSpending || row.flag == .selfTransfer
                created.append(Expense(title: row.merchant, amount: row.amount, category: row.category,
                                       date: row.date, notes: "", paymentMethod: row.method, sourceKey: row.sourceKey,
                                       account: row.account, transfer: transfer ? true : nil))
            }
        }
        expenses.append(contentsOf: created)
        saveExpenses()
        saveReceivedPayments()
        let keys = (UserDefaults.standard.stringArray(forKey: importedRowsKey) ?? []) + rows.map(\.fingerprint)
        UserDefaults.standard.set(keys, forKey: importedRowsKey)
        return created
    }

    /// After you rename / recategorise one transaction, bring the payee's others in
    /// line — but only where they still show the old auto name or no category, so
    /// nothing you set by hand is overwritten. Known merchants keep their names.
    /// `transfer` (when you changed "not my spending") applies to all of them.
    func applyPayeeChoice(sourceKey: String, oldTitle: String, newTitle: String,
                          category: ExpenseCategory, transfer: Bool? = nil, except id: UUID) {
        let key = MerchantNamer.key(sourceKey)
        let rename = !MerchantNamer.isKnown(sourceKey) && newTitle != oldTitle
        for i in expenses.indices where expenses[i].id != id && expenses[i].sourceKey.map(MerchantNamer.key) == key {
            if rename && expenses[i].title == oldTitle { expenses[i].title = newTitle }
            if expenses[i].category == .other { expenses[i].category = category }
            if let transfer, expenses[i].type == .expense { expenses[i].transfer = transfer ? true : nil }
        }
        saveExpenses()
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
    // their full amount counts as both the total and your share. Refunds subtract.
    // Money sent that isn't your spending counts as paid, but not as your share.
    func chargedTotal(_ list: [Expense]) -> Double { list.reduce(0) { $0 + ($1.split?.totalAmount ?? $1.displayAmount) } }
    func myNetTotal(_ list: [Expense]) -> Double { list.reduce(0) { $0 + ($1.isTransfer ? 0 : $1.split?.myShare ?? $1.displayAmount) } }
    func outstandingTotal(_ list: [Expense]) -> Double { list.reduce(0) { $0 + ($1.split?.outstandingTotal ?? 0) } }
    func recoveredTotal(_ list: [Expense]) -> Double { list.reduce(0) { $0 + ($1.split?.settledTotal ?? 0) } }

    // MARK: Card-only (for the Card tab + billing cycles)

    /// Every card transaction (split or not), newest first.
    var creditCardExpenses: [Expense] {
        expensesPaid(via: [.card])
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

    /// Toggle a single participant's settled state and persist.
    func setSettled(_ settled: Bool, participantID: UUID, in expense: Expense) {
        guard let eIndex = expenses.firstIndex(where: { $0.id == expense.id }),
              var split = expenses[eIndex].split,
              let pIndex = split.participants.firstIndex(where: { $0.id == participantID })
        else { return }

        split.participants[pIndex].isSettled = settled
        // Un-settling resets to fully owed, clearing any partial paybacks.
        if !settled { split.participants[pIndex].paidBack = nil }
        expenses[eIndex].split = split
        saveExpenses()
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

    /// Map a split's my-share + participants onto trip members, adding anyone new.
    private func buildShares(from split: SplitInfo, myMember me: TripMember?, members: inout [TripMember]) -> [TripShare] {
        var shares: [TripShare] = []
        if let me, split.myShare > 0 {
            shares.append(TripShare(memberID: me.id, amount: split.myShare))
        }
        for p in split.participants {
            let memberID: UUID
            if let existing = members.first(where: { m in
                if let pc = p.contactIdentifier, let mc = m.contactIdentifier { return pc == mc }
                return !m.isMe && m.name.caseInsensitiveCompare(p.name) == .orderedSame
            }) {
                memberID = existing.id
            } else {
                let newMember = TripMember(name: p.name, contactIdentifier: p.contactIdentifier)
                members.append(newMember)
                memberID = newMember.id
            }
            shares.append(TripShare(memberID: memberID, amount: p.amount))
        }
        return shares
    }

    /// Import an existing split transaction into a trip by reference. The original
    /// stays in its method tab; the trip row links back via sourceExpenseID.
    func importExpenseIntoTrip(_ source: Expense, tripID: UUID) {
        guard let split = source.split,
              let ti = trips.firstIndex(where: { $0.id == tripID }) else { return }
        // Don't import the same transaction twice.
        if trips[ti].expenses.contains(where: { $0.sourceExpenseID == source.id }) { return }

        var members = trips[ti].members
        let me = members.first { $0.isMe }
        let shares = buildShares(from: split, myMember: me, members: &members)
        trips[ti].members = members
        trips[ti].expenses.append(TripExpense(
            title: source.title,
            amount: split.totalAmount,
            category: source.category,
            date: source.date,
            payerID: me?.id ?? members.first?.id ?? UUID(),
            shares: shares,
            notes: source.notes,
            sourceExpenseID: source.id,
            paymentMethod: source.method
        ))
        saveTrips()
    }

    /// Save a trip expense. When you are the payer, it is also recorded as a real
    /// split transaction in the given payment method (default card) so it shows in
    /// the Card / UPI & Cash tab; the two stay linked via sourceExpenseID.
    func saveTripExpense(_ expense: TripExpense, method: PaymentMethod, in tripID: UUID) {
        guard let ti = trips.firstIndex(where: { $0.id == tripID }) else { return }
        var te = expense
        let me = trips[ti].members.first { $0.isMe }

        // If an existing linked transaction exists, update it in place; else create.
        if let me, te.payerID == me.id {
            let others = te.shares.filter { $0.memberID != me.id && $0.amount > 0 }
            let participants: [SplitParticipant] = others.compactMap { s in
                guard let m = trips[ti].members.first(where: { $0.id == s.memberID }) else { return nil }
                return SplitParticipant(name: m.name, contactIdentifier: m.contactIdentifier, amount: s.amount)
            }
            let myShare = te.share(of: me.id)
            let split = SplitInfo(totalAmount: te.amount, myShareIncluded: myShare > 0, participants: participants)

            if let srcID = te.sourceExpenseID, let ei = expenses.firstIndex(where: { $0.id == srcID }) {
                expenses[ei].title = te.title
                expenses[ei].amount = myShare
                expenses[ei].category = te.category
                expenses[ei].date = te.date
                expenses[ei].notes = te.notes
                expenses[ei].split = split
                expenses[ei].paymentMethod = method
            } else {
                let source = Expense(title: te.title, amount: myShare, category: te.category, type: .expense, date: te.date, notes: te.notes, split: split, paymentMethod: method)
                expenses.append(source)
                te.sourceExpenseID = source.id
            }
            te.paymentMethod = method
            saveExpenses()
        } else {
            te.paymentMethod = nil
        }

        if let ei = trips[ti].expenses.firstIndex(where: { $0.id == te.id }) {
            trips[ti].expenses[ei] = te
        } else {
            trips[ti].expenses.append(te)
        }
        saveTrips()
    }

    /// Keep imported trip rows in step with edits to their source transaction.
    private func syncTripExpenses(from source: Expense) {
        guard let split = source.split else { return }
        var changed = false
        for ti in trips.indices {
            var members = trips[ti].members
            let me = members.first { $0.isMe }
            for ei in trips[ti].expenses.indices where trips[ti].expenses[ei].sourceExpenseID == source.id {
                let shares = buildShares(from: split, myMember: me, members: &members)
                var te = trips[ti].expenses[ei]
                te.title = source.title
                te.amount = split.totalAmount
                te.category = source.category
                te.date = source.date
                te.payerID = me?.id ?? te.payerID
                te.shares = shares
                te.notes = source.notes
                te.paymentMethod = source.method
                trips[ti].expenses[ei] = te
                changed = true
            }
            trips[ti].members = members
        }
        if changed { saveTrips() }
    }

    /// Derived personal rows for your share of every trip expense. These are not
    /// stored — they are recomputed from trips, so trip data is never duplicated.
    /// Trip expenses imported from an existing Card/UPI/Cash transaction are
    /// skipped while that source still exists, since your share is already
    /// counted through the original (which stays in its method tab).
    var myTripContributions: [Expense] {
        let storedIDs = Set(expenses.map { $0.id })
        return trips.flatMap { trip -> [Expense] in
            guard let me = trip.myMember else { return [] }
            return trip.expenses.compactMap { te in
                if let src = te.sourceExpenseID, storedIDs.contains(src) { return nil }
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
