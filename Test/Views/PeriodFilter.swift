//
//  PeriodFilter.swift
//  Expense Tracker
//
//  The period + account filter shown at the top of Expenses, Summary, Card and
//  UPI & Cash. Expenses and Summary share one, so Summary always totals exactly
//  what the Expenses list shows.
//

import SwiftUI

struct PeriodFilter {
    enum Period: String, CaseIterable {
        case billingCycle = "Billing Cycle"   // Card tab only
        case today = "Today"
        case yesterday = "Yesterday"
        case week = "This Week"
        case month = "This Month"
        case year = "This Year"
        case all = "All Time"
        case pickMonth = "Pick Month"
        case custom = "Custom Date"
    }

    var period: Period = .month
    var monthDate = Date()
    var customStart = Date()
    var customEnd: Date? = nil
    /// Last 4 digits of the account / card to show; nil shows every account.
    var account: String? = nil

    /// Rows inside the period (or the given billing cycle) and from the chosen account.
    func apply(_ list: [Expense], cycle: ExpenseManager.BillingCycle? = nil) -> [Expense] {
        let range = period == .billingCycle ? cycle.map { ($0.start, $0.end) } : dateRange()
        return list.filter { e in
            (range.map { e.date >= $0.0 && e.date < $0.1 } ?? true) && (account == nil || e.account == account)
        }
    }

    /// Start (inclusive) and end (exclusive) of the period; nil means no date limit.
    private func dateRange() -> (Date, Date)? {
        let calendar = Calendar.current
        let now = Date()
        func span(_ component: Calendar.Component, of date: Date) -> (Date, Date)? {
            calendar.dateInterval(of: component, for: date).map { ($0.start, $0.end) }
        }
        switch period {
        case .today: return span(.day, of: now)
        case .yesterday: return span(.day, of: calendar.date(byAdding: .day, value: -1, to: now)!)
        case .week: return span(.weekOfYear, of: now)
        case .month: return span(.month, of: now)
        case .year: return span(.year, of: now)
        case .pickMonth: return span(.month, of: monthDate)
        case .custom:
            let start = calendar.startOfDay(for: customStart)
            let end = calendar.startOfDay(for: customEnd ?? customStart)
            let (first, last) = start < end ? (start, end) : (end, start)
            return (first, calendar.date(byAdding: .day, value: 1, to: last)!)
        case .all, .billingCycle: return nil
        }
    }
}

/// Period menu (with month / custom date pickers) and, when there's more than
/// one to pick from, an account menu.
struct PeriodFilterBar: View {
    @Binding var filter: PeriodFilter
    var accounts: [String] = []
    var periods: [PeriodFilter.Period] = PeriodFilter.Period.allCases.filter { $0 != .billingCycle }

    private let calendar = Calendar.current
    private var availableYears: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        return (currentYear - 5...currentYear + 1).reversed()
    }
    private var monthBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.month, from: filter.monthDate) },
            set: { newMonth in
                let year = calendar.component(.year, from: filter.monthDate)
                if let d = calendar.date(from: DateComponents(year: year, month: newMonth, day: 1)) {
                    filter.monthDate = d
                }
            }
        )
    }
    private var yearBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.year, from: filter.monthDate) },
            set: { newYear in
                let month = calendar.component(.month, from: filter.monthDate)
                if let d = calendar.date(from: DateComponents(year: newYear, month: month, day: 1)) {
                    filter.monthDate = d
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            Menu {
                ForEach(periods, id: \.self) { period in
                    Button {
                        filter.period = period
                    } label: {
                        HStack {
                            Text(period.rawValue)
                            if filter.period == period {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                menuLabel("Period: \(filter.period.rawValue)")
            }

            // Shown while an account is chosen too, so it can always be cleared.
            if !accounts.isEmpty || filter.account != nil {
                Menu {
                    Button {
                        filter.account = nil
                    } label: {
                        HStack {
                            Text("All accounts")
                            if filter.account == nil { Image(systemName: "checkmark") }
                        }
                    }
                    ForEach(accounts, id: \.self) { account in
                        Button {
                            filter.account = account
                        } label: {
                            HStack {
                                Text("••\(account)")
                                if filter.account == account { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    menuLabel("Account: \(filter.account.map { "••\($0)" } ?? "All")")
                }
            }

            // Month + Year Picker (shown when Pick Month is selected)
            if filter.period == .pickMonth {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray6))
                )
            }

            // Custom Date: From + optional To (shown when Custom Date is selected)
            if filter.period == .custom {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("From Date")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        DatePicker("", selection: $filter.customStart, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .onChange(of: filter.customStart, perform: { _ in
                                filter.customEnd = nil
                            })
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("To Date (optional)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if filter.customEnd != nil {
                                Button("Clear") {
                                    filter.customEnd = nil
                                }
                                .font(.caption)
                            }
                        }
                        if filter.customEnd != nil {
                            DatePicker("", selection: Binding(
                                get: { filter.customEnd ?? filter.customStart },
                                set: { filter.customEnd = $0 }
                            ), displayedComponents: .date)
                                .datePickerStyle(.compact)
                        } else {
                            Button(action: {
                                filter.customEnd = filter.customStart
                            }) {
                                Text("Add end date for range")
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray6))
                )
            }
        }
        .buttonStyle(.borderless)   // inside a List row, each control gets its own tap
    }

    private func menuLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
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

    private func monthName(for month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale.current
        guard let date = calendar.date(from: DateComponents(month: month, day: 1)),
              (1...12).contains(month) else { return "" }
        return formatter.string(from: date)
    }
}
