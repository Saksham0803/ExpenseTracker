//
//  Expense.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import Foundation

struct Expense: Identifiable, Codable {
    let id: UUID
    var title: String
    var amount: Double
    var category: ExpenseCategory
    var date: Date
    var notes: String
    
    init(id: UUID = UUID(), title: String, amount: Double, category: ExpenseCategory, date: Date = Date(), notes: String = "") {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
        self.notes = notes
    }
}

enum ExpenseCategory: String, CaseIterable, Codable {
    case food = "Food"
    case transportation = "Transportation"
    case shopping = "Shopping"
    case entertainment = "Entertainment"
    case bills = "Bills"
    case healthcare = "Healthcare"
    case education = "Education"
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
        case .grocery: return "teal"
        case .other: return "gray"
        }
    }
}
