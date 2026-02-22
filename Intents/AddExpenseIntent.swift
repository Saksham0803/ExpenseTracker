//
//  AddExpenseIntent.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import AppIntents
import Foundation

// Make ExpenseCategory available to App Intents
extension ExpenseCategory: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Expense Category")
    }
    
    static var caseDisplayRepresentations: [ExpenseCategory: DisplayRepresentation] {
        [
            .food: DisplayRepresentation(title: "Food", image: DisplayRepresentation.Image(systemName: "fork.knife")),
            .transportation: DisplayRepresentation(title: "Transportation", image: DisplayRepresentation.Image(systemName: "car.fill")),
            .shopping: DisplayRepresentation(title: "Shopping", image: DisplayRepresentation.Image(systemName: "bag.fill")),
            .entertainment: DisplayRepresentation(title: "Entertainment", image: DisplayRepresentation.Image(systemName: "tv.fill")),
            .bills: DisplayRepresentation(title: "Bills", image: DisplayRepresentation.Image(systemName: "doc.text.fill")),
            .healthcare: DisplayRepresentation(title: "Healthcare", image: DisplayRepresentation.Image(systemName: "cross.case.fill")),
            .education: DisplayRepresentation(title: "Education", image: DisplayRepresentation.Image(systemName: "book.fill")),
            .grocery: DisplayRepresentation(title: "Grocery", image: DisplayRepresentation.Image(systemName: "cart.fill")),
            .other: DisplayRepresentation(title: "Other", image: DisplayRepresentation.Image(systemName: "ellipsis.circle.fill"))
        ]
    }
}

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Add a new expense to your expense tracker.")
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Title", description: "What did you spend money on?")
    var title: String
    
    @Parameter(title: "Amount", description: "How much did you spend?")
    var amount: Double
    
    @Parameter(title: "Category", description: "What category is this expense?")
    var category: ExpenseCategory
    
    @Parameter(title: "Notes", description: "Optional notes about this expense")
    var notes: String?
    
    @Parameter(title: "Date", description: "When was this expense?")
    var date: Date?
    
    static var parameterSummary: some ParameterSummary {
        Summary("Add expense: \(\.$title) - \(\.$amount) in \(\.$category)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let expense = Expense(
            title: title,
            amount: amount,
            category: category,
            date: date ?? Date(),
            notes: notes ?? ""
        )
        
        // Get the shared ExpenseManager instance
        let expenseManager = ExpenseManager.shared
        expenseManager.addExpense(expense)
        
        return .result(dialog: "Added expense: \(title) - \(formatCurrency(amount))")
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

// App Shortcuts Provider
struct ExpenseTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add expense in \(.applicationName)",
                "Log expense in \(.applicationName)",
                "Record expense in \(.applicationName)",
                "Track expense in \(.applicationName)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle"
        )
    }
    
    static var shortcutTileColor: ShortcutTileColor = .blue
}
