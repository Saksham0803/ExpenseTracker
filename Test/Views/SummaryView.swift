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
        case today = "Today"
        case yesterday = "Yesterday"
        case week = "This Week"
        case month = "This Month"
        case year = "This Year"
        case all = "All Time"
        case pickMonth = "Pick Month"
        case custom = "Custom Date"
    }
    
    @State private var selectedCustomStartDate = Date()
    @State private var selectedCustomEndDate: Date? = nil
    @State private var selectedMonthDate = Date()
    @State private var showingDatePicker = false
    
    private let calendar = Calendar.current
    private var availableYears: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        return (currentYear - 5...currentYear + 1).reversed()
    }
    private var monthBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.month, from: selectedMonthDate) },
            set: { newMonth in
                let year = calendar.component(.year, from: selectedMonthDate)
                if let d = calendar.date(from: DateComponents(year: year, month: newMonth, day: 1)) {
                    selectedMonthDate = d
                }
            }
        )
    }
    private var yearBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.year, from: selectedMonthDate) },
            set: { newYear in
                let month = calendar.component(.month, from: selectedMonthDate)
                if let d = calendar.date(from: DateComponents(year: newYear, month: month, day: 1)) {
                    selectedMonthDate = d
                }
            }
        )
    }
    
    private var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedPeriod {
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            return expenseManager.expensesForDateRange(start: startOfDay, end: endOfDay)
            
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            let startOfDay = calendar.startOfDay(for: yesterday)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            return expenseManager.expensesForDateRange(start: startOfDay, end: endOfDay)
            
        case .week:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return expenseManager.expensesForDateRange(start: startOfWeek, end: now)
            
        case .month:
            return expenseManager.expensesForMonth(now)
            
        case .year:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now))!
            return expenseManager.expensesForDateRange(start: startOfYear, end: now)
            
        case .pickMonth:
            return expenseManager.expensesForMonth(selectedMonthDate)
            
        case .custom:
            let startDay = calendar.startOfDay(for: selectedCustomStartDate)
            if let end = selectedCustomEndDate {
                let endDayStart = calendar.startOfDay(for: end)
                let (first, last) = startDay < endDayStart ? (startDay, endDayStart) : (endDayStart, startDay)
                let endOfLast = calendar.date(byAdding: .day, value: 1, to: last)!
                return expenseManager.expensesForDateRange(start: first, end: endOfLast)
            } else {
                let endOfStart = calendar.date(byAdding: .day, value: 1, to: startDay)!
                return expenseManager.expensesForDateRange(start: startDay, end: endOfStart)
            }
            
        case .all:
            return expenseManager.expenses
        }
    }
    
    private var totalAmount: Double {
        filteredExpenses.reduce(0) { $0 + $1.displayAmount }
    }
    
    private var totalSpent: Double {
        filteredExpenses.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
    
    private var totalRefunded: Double {
        filteredExpenses.filter { $0.type == .refund }.reduce(0) { $0 + $1.amount }
    }
    
    private var categoryBreakdown: [(category: ExpenseCategory, amount: Double, percentage: Double)] {
        let categoryTotals = Dictionary(grouping: filteredExpenses, by: { $0.category })
            .mapValues { expenses in
                expenses.reduce(0) { $0 + $1.displayAmount }
            }
        
        return categoryTotals.map { (category, amount) in
            // Calculate percentage based on net total (use abs for denominator to avoid division issues)
            // But base calculation on net total, not just totalSpent
            let percentage = abs(totalAmount) > 0 ? (amount / totalAmount) * 100 : 0
            return (category, amount, abs(percentage))
        }
        .sorted { abs($0.amount) > abs($1.amount) }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Total Amount Card
                    VStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text("Net Total")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(formatCurrency(totalAmount))
                                .font(.system(size: 42, weight: .bold))
                                .foregroundColor(totalAmount >= 0 ? .primary : .green)
                        }
                        
                        HStack(spacing: 20) {
                            VStack(spacing: 4) {
                                Text("Spent")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatCurrency(totalSpent))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                            }
                            
                            VStack(spacing: 4) {
                                Text("Refunded")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatCurrency(totalRefunded))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    
                    // Period Picker - Dropdown Menu
                    VStack(spacing: 12) {
                        Menu {
                            ForEach(TimePeriod.allCases, id: \.self) { period in
                                Button(action: {
                                    selectedPeriod = period
                                }) {
                                    HStack {
                                        Text(period.rawValue)
                                        if selectedPeriod == period {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Period: \(selectedPeriod.rawValue)")
                                    .font(.body)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.systemGray6))
                            )
                        }
                        
                        // Month + Year Picker (shown when Pick Month is selected)
                        if selectedPeriod == .pickMonth {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Select Month")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 16) {
                                    Picker("Month", selection: monthBinding) {
                                        ForEach(1...12, id: \.self) { month in
                                            Text(monthName(for: month)).tag(month)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    Picker("Year", selection: yearBinding) {
                                        ForEach(availableYears, id: \.self) { year in
                                            Text(String(year)).tag(year)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.systemGray6))
                            )
                        }
                        
                        // Custom Date: From + optional To (shown when Custom Date is selected)
                        if selectedPeriod == .custom {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("From Date")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    DatePicker("", selection: $selectedCustomStartDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .onChange(of: selectedCustomStartDate, perform: { _ in
                                            selectedCustomEndDate = nil
                                        })
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("To Date (optional)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        if selectedCustomEndDate != nil {
                                            Button("Clear") {
                                                selectedCustomEndDate = nil
                                            }
                                            .font(.caption)
                                        }
                                    }
                                    if let _ = selectedCustomEndDate {
                                        DatePicker("", selection: Binding(
                                            get: { selectedCustomEndDate ?? selectedCustomStartDate },
                                            set: { selectedCustomEndDate = $0 }
                                        ), displayedComponents: .date)
                                            .datePickerStyle(.compact)
                                    } else {
                                        Button(action: {
                                            selectedCustomEndDate = selectedCustomStartDate
                                        }) {
                                            Text("Add end date for range")
                                                .font(.subheadline)
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.systemGray6))
                            )
                        }
                    }
                    
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
                                    value: formatCurrency(abs(totalAmount) / Double(filteredExpenses.count)),
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
    
    private func monthName(for month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale.current
        guard let date = calendar.date(from: DateComponents(month: month, day: 1)),
              (1...12).contains(month) else { return "" }
        return formatter.string(from: date)
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
                        .foregroundColor(category.colorValue)
                        .font(.system(size: 20))
                        .frame(width: 30)
                    
                    Text(category.rawValue)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatCurrency(amount))
                            .font(.headline)
                            .foregroundColor(amount >= 0 ? .primary : .green)
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
                        .fill(amount >= 0 ? category.colorValue : Color.green)
                        .frame(width: geometry.size.width * CGFloat(abs(percentage) / 100), height: 8)
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
        expenses.reduce(0) { $0 + $1.displayAmount }
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
                                .foregroundColor(categoryTotal >= 0 ? .primary : .green)
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
            ExpenseEditorView(editing: expense)
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
                    Text(formatDateAndTime(expense.date))
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
    SummaryView()
        .environmentObject(ExpenseManager())
}
