//
//  AddExpenseView.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import SwiftUI

struct AddExpenseView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager
    
    @State private var title: String = ""
    @State private var amount: String = ""
    @State private var selectedCategory: ExpenseCategory = .other
    @State private var selectedType: ExpenseType = .expense
    @State private var selectedDate: Date = Date()
    @State private var notes: String = ""
    
    let expense: Expense?
    
    init(expense: Expense? = nil) {
        self.expense = expense
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Expense Details")) {
                    TextField("Title", text: $title)
                    
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Picker("Type", selection: $selectedType) {
                        ForEach([ExpenseType.expense, ExpenseType.refund], id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.rawValue)
                            }
                            .tag(type)
                        }
                    }
                    
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue)
                            }
                            .tag(category)
                        }
                    }
                    
                    DatePicker("Date & Time", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section(header: Text("Notes")) {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(expense == nil ? "Add Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveExpense()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let expense = expense {
                    loadExpense(expense)
                }
            }
        }
    }
    
    private var isValid: Bool {
        !title.isEmpty && !amount.isEmpty && Double(amount) != nil && Double(amount)! > 0
    }
    
    private func loadExpense(_ expense: Expense) {
        title = expense.title
        amount = String(format: "%.2f", expense.amount)
        selectedCategory = expense.category
        selectedType = expense.type
        selectedDate = expense.date
        notes = expense.notes
    }
    
    private func saveExpense() {
        guard let amountValue = Double(amount), amountValue > 0 else { return }
        
        // Ensure date is stored with IST timezone
        let istTimeZone = TimeZone(identifier: "Asia/Kolkata")!
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: istTimeZone, from: selectedDate)
        let istDate = calendar.date(from: components) ?? selectedDate
        
        let newExpense = Expense(
            id: expense?.id ?? UUID(),
            title: title,
            amount: amountValue,
            category: selectedCategory,
            type: selectedType,
            date: istDate,
            notes: notes
        )
        
        if expense != nil {
            expenseManager.updateExpense(newExpense)
        } else {
            expenseManager.addExpense(newExpense)
        }
        
        dismiss()
    }
}

#Preview {
    AddExpenseView()
        .environmentObject(ExpenseManager())
}
