//
//  Trip.swift
//  Expense Tracker
//
//  Group-trip ledger: any member can pay, expenses split among members, and a
//  Splitwise-style settlement nets everyone out into the fewest transfers.
//

import Foundation

struct TripMember: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var contactIdentifier: String?
    var isMe: Bool

    nonisolated init(id: UUID = UUID(), name: String, contactIdentifier: String? = nil, isMe: Bool = false) {
        self.id = id
        self.name = name
        self.contactIdentifier = contactIdentifier
        self.isMe = isMe
    }
}

/// One member's share of a single expense.
struct TripShare: Codable, Hashable {
    var memberID: UUID
    var amount: Double
}

struct TripExpense: Identifiable, Codable {
    let id: UUID
    var title: String
    var amount: Double
    var category: ExpenseCategory
    var date: Date
    /// The member who actually paid this expense.
    var payerID: UUID
    /// Per-member shares; these sum to `amount`.
    var shares: [TripShare]
    var notes: String
    /// Set when this row was imported from an existing Card/UPI/Cash transaction.
    /// The original stays in its method tab, so your share is already counted
    /// there — this link lets us avoid double-counting it in your totals.
    var sourceExpenseID: UUID?

    nonisolated init(id: UUID = UUID(), title: String, amount: Double, category: ExpenseCategory, date: Date = Date(), payerID: UUID, shares: [TripShare], notes: String = "", sourceExpenseID: UUID? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
        self.payerID = payerID
        self.shares = shares
        self.notes = notes
        self.sourceExpenseID = sourceExpenseID
    }

    func share(of memberID: UUID) -> Double {
        shares.first { $0.memberID == memberID }?.amount ?? 0
    }
}

struct Trip: Identifiable, Codable {
    let id: UUID
    var name: String
    var startDate: Date
    var endDate: Date?
    var members: [TripMember]
    var expenses: [TripExpense]
    /// Marked true when you "end" the trip and settle up.
    var isClosed: Bool

    nonisolated init(id: UUID = UUID(), name: String, startDate: Date = Date(), endDate: Date? = nil, members: [TripMember] = [], expenses: [TripExpense] = [], isClosed: Bool = false) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.members = members
        self.expenses = expenses
        self.isClosed = isClosed
    }
}

/// One transfer in the settlement plan: `from` pays `to` the given amount.
struct Settlement: Identifiable {
    let id = UUID()
    let from: TripMember
    let to: TripMember
    let amount: Double
}

extension Trip {
    var total: Double { expenses.reduce(0) { $0 + $1.amount } }

    func member(_ id: UUID) -> TripMember? { members.first { $0.id == id } }

    var myMember: TripMember? { members.first { $0.isMe } }

    /// Total this member actually paid out of pocket.
    func paid(by memberID: UUID) -> Double {
        expenses.filter { $0.payerID == memberID }.reduce(0) { $0 + $1.amount }
    }

    /// Total this member is responsible for (their share across all expenses).
    func share(of memberID: UUID) -> Double {
        expenses.reduce(0) { $0 + $1.share(of: memberID) }
    }

    /// Net position: positive means the group owes them, negative means they owe.
    func net(of memberID: UUID) -> Double {
        paid(by: memberID) - share(of: memberID)
    }

    /// My own share of the whole trip — what counts as my personal spending.
    var myShareTotal: Double {
        guard let me = myMember else { return 0 }
        return share(of: me.id)
    }

    func categoryBreakdown() -> [(category: ExpenseCategory, amount: Double)] {
        Dictionary(grouping: expenses, by: { $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
            .map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    /// Minimal set of transfers that clears every balance (greedy min-cash-flow).
    func settlements() -> [Settlement] {
        func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

        var creditors: [(member: TripMember, amount: Double)] = []
        var debtors: [(member: TripMember, amount: Double)] = []
        for m in members {
            let n = round2(net(of: m.id))
            if n > 0.009 { creditors.append((m, n)) }
            else if n < -0.009 { debtors.append((m, -n)) }
        }
        // Largest balances first so we clear the biggest debts in the fewest hops.
        creditors.sort { $0.amount > $1.amount }
        debtors.sort { $0.amount > $1.amount }

        var result: [Settlement] = []
        var ci = 0, di = 0
        while ci < creditors.count && di < debtors.count {
            let pay = round2(min(creditors[ci].amount, debtors[di].amount))
            if pay > 0 {
                result.append(Settlement(from: debtors[di].member, to: creditors[ci].member, amount: pay))
            }
            creditors[ci].amount = round2(creditors[ci].amount - pay)
            debtors[di].amount = round2(debtors[di].amount - pay)
            if creditors[ci].amount <= 0.009 { ci += 1 }
            if debtors[di].amount <= 0.009 { di += 1 }
        }
        return result
    }
}
