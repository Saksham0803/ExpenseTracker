//
//  AddExpenseIntent.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import AppIntents
import Foundation

// Make ExpenseType available to App Intents
extension ExpenseType: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Expense Type")
    }
    
    nonisolated static var caseDisplayRepresentations: [ExpenseType: DisplayRepresentation] {
        [
            .expense: DisplayRepresentation(title: "Expense", image: DisplayRepresentation.Image(systemName: "arrow.down.circle.fill")),
            .refund: DisplayRepresentation(title: "Refund", image: DisplayRepresentation.Image(systemName: "arrow.up.circle.fill"))
        ]
    }
}

// Make ExpenseCategory available to App Intents
extension ExpenseCategory: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Expense Category")
    }
    
    nonisolated static var caseDisplayRepresentations: [ExpenseCategory: DisplayRepresentation] {
        [
            .food: DisplayRepresentation(title: "Food", image: DisplayRepresentation.Image(systemName: "fork.knife")),
            .transportation: DisplayRepresentation(title: "Transportation", image: DisplayRepresentation.Image(systemName: "car.fill")),
            .shopping: DisplayRepresentation(title: "Shopping", image: DisplayRepresentation.Image(systemName: "bag.fill")),
            .entertainment: DisplayRepresentation(title: "Entertainment", image: DisplayRepresentation.Image(systemName: "tv.fill")),
            .bills: DisplayRepresentation(title: "Bills", image: DisplayRepresentation.Image(systemName: "doc.text.fill")),
            .healthcare: DisplayRepresentation(title: "Healthcare", image: DisplayRepresentation.Image(systemName: "cross.case.fill")),
            .education: DisplayRepresentation(title: "Education", image: DisplayRepresentation.Image(systemName: "book.fill")),
            .quickCommerce: DisplayRepresentation(title: "Quick Commerce", image: DisplayRepresentation.Image(systemName: "bolt.circle.fill")),
            .investment: DisplayRepresentation(title: "Investment", image: DisplayRepresentation.Image(systemName: "chart.line.uptrend.xyaxis")),
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
    
    @Parameter(title: "Type", description: "Is this an expense or a refund?")
    var type: ExpenseType
    
    @Parameter(title: "Notes", description: "Notes about this expense (optional - say 'none' to skip)")
    var notes: String
    
    @Parameter(title: "Date", description: "When was this expense?")
    var date: Date?
    
    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$type): \(\.$title) - \(\.$amount) in \(\.$category)")
    }
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Create expense data
        let expenseTitle = title
        let expenseAmount = amount
        let expenseCategory = category
        let expenseType = type
        let expenseNotes = notes.isEmpty || notes.lowercased() == "none" ? "" : notes
        
        // Convert date to IST timezone
        let istTimeZone = TimeZone(identifier: "Asia/Kolkata")!
        let inputDate = date ?? Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: istTimeZone, from: inputDate)
        let expenseDate = calendar.date(from: components) ?? inputDate
        
        // Get the shared ExpenseManager instance and add expense on main actor
        await MainActor.run {
            let expense = Expense(
                title: expenseTitle,
                amount: expenseAmount,
                category: expenseCategory,
                type: expenseType,
                date: expenseDate,
                notes: expenseNotes
            )
            ExpenseManager.shared.addExpense(expense)
        }
        
        // Return success result with dialog
        let typeText = type == .refund ? "refund" : "expense"
        return .result(dialog: IntentDialog("Added \(typeText): \(title) - \(formatCurrency(amount))"))
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
