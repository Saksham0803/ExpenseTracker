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

/// Auto-capture intent: hand it a bank/UPI message (from a Shortcuts automation),
/// it parses and logs the transaction flagged for a quick note, and nudges you.
struct LogTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Transaction from Message"
    static var description = IntentDescription("Reads a bank/UPI message, logs the transaction, and flags it for a quick note.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Message", description: "The transaction SMS or notification text")
    var message: String

    // Runs silently (no pop-up): a logged transaction gets its own notification,
    // and every run is listed in Shortcuts setup so a misfire can be diagnosed.
    func perform() async throws -> some IntentResult {
        let text = message
        // Broad triggers ("Dr.", "Sent") also catch offers and chats — only log real alerts.
        guard TransactionParser.looksLikeBankTransaction(text) else {
            await MainActor.run { Self.recordRun(text, outcome: "Skipped — doesn't look like a bank alert") }
            return .result()
        }
        guard let parsed = TransactionParser().parseMessage(text), parsed.amount > 0 else {
            await MainActor.run { Self.recordRun(text, outcome: "Skipped — no amount found") }
            return .result()
        }
        // One SMS can match two automations (e.g. "Dr." and "credited"): log it once.
        if await MainActor.run(body: { Self.seenRecently(text) }) {
            await MainActor.run { Self.recordRun(text, outcome: "Already logged") }
            return .result()
        }

        // Store the date in IST, matching the rest of the app.
        let istTimeZone = TimeZone(identifier: "Asia/Kolkata")!
        let calendar = Calendar.current
        let base = parsed.date ?? Date()
        let components = calendar.dateComponents(in: istTimeZone, from: base)
        let date = calendar.date(from: components) ?? base

        let rawMerchant = parsed.merchant
        let amount = parsed.amount
        let parsedCategory = parsed.category ?? .other
        let method = parsed.method
        let account = parsed.account
        // Readable name + category: what you've taught the app, then known merchants.
        let named = await MainActor.run { MerchantNamer.resolve(rawMerchant) }
        // Payees you've marked "not my spending" (e.g. family) stay out of Expenses.
        let notSpending = await MainActor.run { MerchantNamer.notSpending(rawMerchant) == true }
        let merchant = named.name

        // Money in: park it for matching against who owes you; never counts as spending.
        if parsed.isCredit {
            let raw = parsed.rawMessage
            await MainActor.run {
                ExpenseManager.shared.addReceivedPayment(
                    ReceivedPayment(amount: amount, sender: merchant, date: date, rawMessage: raw,
                                    method: method, account: account)
                )
                NotificationManager.shared.notifyReceived(sender: merchant, amount: amount)
                Self.recordRun(text, outcome: "Money received: \(NotificationManager.currency(amount)) from \(merchant)")
            }
            return .result()
        }

        await MainActor.run {
            let expense = Expense(
                title: merchant,
                amount: amount,
                category: named.category ?? parsedCategory,
                type: .expense,
                date: date,
                notes: "",
                paymentMethod: method,
                needsReview: true,
                sourceKey: rawMerchant,
                account: account,
                transfer: notSpending ? true : nil
            )
            ExpenseManager.shared.addExpense(expense)
            NotificationManager.shared.notifyLogged(title: merchant, amount: amount)
            Self.recordRun(text, outcome: "Logged: \(NotificationManager.currency(amount)) at \(merchant)")
        }

        return .result()
    }
}

/// One auto-capture run: the text the automation passed in and what happened.
struct CaptureRun: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let text: String
    let outcome: String
}

extension LogTransactionIntent {
    private static let runsKey = "RecentCaptureRuns"

    /// The last 10 runs, newest first (shown in Shortcuts setup).
    static var recentRuns: [CaptureRun] {
        guard let data = UserDefaults.standard.data(forKey: runsKey),
              let runs = try? JSONDecoder().decode([CaptureRun].self, from: data) else { return [] }
        return runs
    }

    @MainActor static func recordRun(_ text: String, outcome: String) {
        let run = CaptureRun(date: Date(), text: String(text.prefix(300)), outcome: outcome)
        if let data = try? JSONEncoder().encode(Array(([run] + recentRuns).prefix(10))) {
            UserDefaults.standard.set(data, forKey: runsKey)
        }
    }

    /// True if this exact message was captured in the last 10 minutes; records it otherwise.
    @MainActor static func seenRecently(_ message: String) -> Bool {
        let key = "RecentCapturedMessages"
        let now = Date().timeIntervalSince1970
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var recent = (UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:])
            .filter { now - $0.value < 600 }
        let seen = recent[text] != nil
        recent[text] = now
        UserDefaults.standard.set(recent, forKey: key)
        return seen
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
