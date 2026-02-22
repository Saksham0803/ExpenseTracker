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
                    .fill(Color(expense.category.color).opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: expense.category.icon)
                    .foregroundColor(Color(expense.category.color))
                    .font(.system(size: 20))
            }
            
            // Expense Details
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack {
                    Text(expense.category.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(expense.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Amount
            Text(formatCurrency(expense.amount))
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

#Preview {
    ExpenseListView()
        .environmentObject(ExpenseManager())
}
