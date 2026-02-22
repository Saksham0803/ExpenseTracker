//
//  SummaryView.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    @State private var selectedPeriod: TimePeriod = .month
    
    enum TimePeriod: String, CaseIterable {
        case week = "This Week"
        case month = "This Month"
        case year = "This Year"
        case all = "All Time"
    }
    
    private var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedPeriod {
        case .week:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return expenseManager.expensesForDateRange(start: startOfWeek, end: now)
        case .month:
            return expenseManager.expensesForMonth(now)
        case .year:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now))!
            return expenseManager.expensesForDateRange(start: startOfYear, end: now)
        case .all:
            return expenseManager.expenses
        }
    }
    
    private var totalAmount: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
    }
    
    private var categoryBreakdown: [(category: ExpenseCategory, amount: Double, percentage: Double)] {
        let categoryTotals = Dictionary(grouping: filteredExpenses, by: { $0.category })
            .mapValues { expenses in
                expenses.reduce(0) { $0 + $1.amount }
            }
        
        return categoryTotals.map { (category, amount) in
            let percentage = totalAmount > 0 ? (amount / totalAmount) * 100 : 0
            return (category, amount, percentage)
        }
        .sorted { $0.amount > $1.amount }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Total Amount Card
                    VStack(spacing: 8) {
                        Text("Total Expenses")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(formatCurrency(totalAmount))
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    
                    // Period Picker
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(TimePeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Category Breakdown
                    if !categoryBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("By Category")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(categoryBreakdown, id: \.category) { item in
                                NavigationLink(destination: CategoryExpensesView(
                                    category: item.category,
                                    expenses: filteredExpenses.filter { $0.category == item.category }
                                )) {
                                    CategoryRowView(
                                        category: item.category,
                                        amount: item.amount,
                                        percentage: item.percentage
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "chart.pie")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text("No expenses for this period")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    }
                    
                    // Statistics
                    if !filteredExpenses.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Statistics")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            HStack(spacing: 20) {
                                StatCardView(
                                    title: "Count",
                                    value: "\(filteredExpenses.count)",
                                    icon: "number"
                                )
                                
                                StatCardView(
                                    title: "Average",
                                    value: formatCurrency(totalAmount / Double(filteredExpenses.count)),
                                    icon: "chart.bar"
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Summary")
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

struct CategoryRowView: View {
    let category: ExpenseCategory
    let amount: Double
    let percentage: Double
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: category.icon)
                        .foregroundColor(Color(category.color))
                        .font(.system(size: 20))
                        .frame(width: 30)
                    
                    Text(category.rawValue)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatCurrency(amount))
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(String(format: "%.1f%%", percentage))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(category.color))
                        .frame(width: geometry.size.width * CGFloat(percentage / 100), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.blue)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

struct CategoryExpensesView: View {
    let category: ExpenseCategory
    let expenses: [Expense]
    @State private var selectedExpense: Expense?
    
    private var categoryTotal: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        List {
            if expenses.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No expenses in this category")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // Summary Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatCurrency(categoryTotal))
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Count")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(expenses.count)")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Expenses List
                Section {
                    ForEach(expenses.sorted { $0.date > $1.date }) { expense in
                        CategoryExpenseRowView(expense: expense)
                            .onTapGesture {
                                selectedExpense = expense
                            }
                    }
                }
            }
        }
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedExpense) { expense in
            AddExpenseView(expense: expense)
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

struct CategoryExpenseRowView: View {
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
                    Text(expense.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !expense.notes.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(expense.notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
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
    SummaryView()
        .environmentObject(ExpenseManager())
}
