//
//  ExpenseListView.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import SwiftUI

struct ExpenseListView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    @State private var showingAddExpense = false
    @State private var showingMessageImport = false
    @State private var showingShortcutsSetup = false
    @State private var showingBackup = false
    @State private var selectedExpense: Expense?
    @State private var searchText = ""
    
    private var filteredExpenses: [Expense] {
        if searchText.isEmpty {
            return expenseManager.expenses.sorted { $0.date > $1.date }
        } else {
            return expenseManager.expenses
                .filter { $0.title.localizedCaseInsensitiveContains(searchText) || 
                         $0.category.rawValue.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.date > $1.date }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if filteredExpenses.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No expenses yet")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Tap the + button to add your first expense")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filteredExpenses) { expense in
                            ExpenseRowView(expense: expense)
                                .onTapGesture {
                                    selectedExpense = expense
                                }
                        }
                        .onDelete(perform: deleteExpenses)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Expenses")
            .searchable(text: $searchText, prompt: "Search expenses")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        showingBackup = true
                    } label: {
                        Image(systemName: "externaldrive.badge.icloud")
                    }
                    
                    Button {
                        showingShortcutsSetup = true
                    } label: {
                        Image(systemName: "app.badge")
                    }
                    
                    Button {
                        showingMessageImport = true
                    } label: {
                        Image(systemName: "message.badge")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddExpense = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView()
            }
            .sheet(isPresented: $showingMessageImport) {
                MessageImportView()
            }
            .sheet(isPresented: $showingShortcutsSetup) {
                ShortcutsSetupView()
            }
            .sheet(isPresented: $showingBackup) {
                BackupView()
            }
            .sheet(item: $selectedExpense) { expense in
                AddExpenseView(expense: expense)
            }
        }
    }
    
    private func deleteExpenses(at offsets: IndexSet) {
        expenseManager.deleteExpense(at: offsets)
    }
}

struct ExpenseRowView: View {
    let expense: Expense
    
    var body: some View {
        HStack(spacing: 12) {
            // Category Icon
            ZStack {
                Circle()
                    .fill(expense.category.colorValue.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: expense.category.icon)
                    .foregroundColor(expense.category.colorValue)
                    .font(.system(size: 20))
            }
            
            // Expense Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(expense.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if expense.type == .refund {
                        Text("(Refund)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                HStack {
                    Text(expense.category.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(formatDateAndTime(expense.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Amount
            HStack(spacing: 4) {
                if expense.type == .refund {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Text(formatCurrency(expense.displayAmount))
                    .font(.headline)
                    .foregroundColor(expense.type == .refund ? .green : .primary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
    
    private func formatDateAndTime(_ date: Date) -> String {
        let istTimeZone = TimeZone(identifier: "Asia/Kolkata")!
        let formatter = DateFormatter()
        formatter.timeZone = istTimeZone
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

#Preview {
    ExpenseListView()
        .environmentObject(ExpenseManager())
}
