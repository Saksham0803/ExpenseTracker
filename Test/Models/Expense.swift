//
//  Expense.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import Foundation
import SwiftUI

enum ExpenseType: String, CaseIterable, Codable, Sendable {
    case expense = "Expense"
    case refund = "Refund"
    
    var icon: String {
        switch self {
        case .expense: return "arrow.down.circle.fill"
        case .refund: return "arrow.up.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .expense: return .red
        case .refund: return .green
        }
    }
}

/// Lightweight back-reference from a derived personal row to its trip expense.
struct TripExpenseRef: Codable, Hashable {
    var tripID: UUID
    var tripName: String
}

enum PaymentMethod: String, CaseIterable, Codable, Sendable {
    case cash = "Cash"
    case upi = "UPI"
    case card = "Card"

    var icon: String {
        switch self {
        case .cash: return "banknote.fill"
        case .upi: return "indianrupeesign.circle.fill"
        case .card: return "creditcard.fill"
        }
    }
}

struct Expense: Identifiable, Codable {
    let id: UUID
    var title: String
    var amount: Double
    var category: ExpenseCategory
    var type: ExpenseType
    var date: Date
    var notes: String
    /// Present when this charge was split with other people (paid by you and
    /// recovered from friends). `amount` still holds only your own share.
    var split: SplitInfo?
    /// How the payment was made. Optional for backward compatibility with data
    /// saved before this field existed — read `method` instead.
    var paymentMethod: PaymentMethod?
    /// Set only on synthesized rows that mirror your share of a trip expense.
    /// These are computed (never stored), so they never double-count.
    var tripRef: TripExpenseRef?

    nonisolated init(id: UUID = UUID(), title: String, amount: Double, category: ExpenseCategory, type: ExpenseType = .expense, date: Date = Date(), notes: String = "", split: SplitInfo? = nil, paymentMethod: PaymentMethod? = nil, tripRef: TripExpenseRef? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.type = type
        self.date = date
        self.notes = notes
        self.split = split
        self.paymentMethod = paymentMethod
        self.tripRef = tripRef
    }

    /// True for a derived row that represents your share of a trip expense.
    var isTripContribution: Bool { tripRef != nil }

    // Computed property for display amount (negative for refunds)
    var displayAmount: Double {
        type == .refund ? -amount : amount
    }

    /// Effective payment method. Legacy split records predate the field and were
    /// always card, so fall back to card when a split exists, otherwise cash.
    var method: PaymentMethod {
        paymentMethod ?? (split != nil ? .card : .cash)
    }

    /// True when this expense was split with other people (any payment method).
    var isSplit: Bool {
        split != nil
    }

    /// Retained for compatibility; a split now exists on any payment method.
    var isCreditCardSplit: Bool { isSplit }
}

enum ExpenseCategory: String, CaseIterable, Codable, Sendable {
    case food = "Food"
    case transportation = "Transportation"
    case shopping = "Shopping"
    case entertainment = "Entertainment"
    case bills = "Bills"
    case healthcare = "Healthcare"
    case education = "Education"
    case quickCommerce = "Quick Commerce"
    case investment = "Investment"
    case grocery = "Grocery"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transportation: return "car.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "tv.fill"
        case .bills: return "doc.text.fill"
        case .healthcare: return "cross.case.fill"
        case .education: return "book.fill"
        case .quickCommerce: return "bolt.circle.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .grocery: return "cart.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .food: return "orange"
        case .transportation: return "blue"
        case .shopping: return "pink"
        case .entertainment: return "purple"
        case .bills: return "red"
        case .healthcare: return "green"
        case .education: return "indigo"
        case .quickCommerce: return "yellow"
        case .investment: return "cyan"
        case .grocery: return "teal"
        case .other: return "gray"
        }
    }
    
    var colorValue: Color {
        switch self {
        case .food: return .orange
        case .transportation: return .blue
        case .shopping: return .pink
        case .entertainment: return .purple
        case .bills: return .red
        case .healthcare: return .green
        case .education: return .indigo
        case .quickCommerce: return .yellow
        case .investment: return .cyan
        case .grocery: return .teal
        case .other: return .gray
        }
    }
}
