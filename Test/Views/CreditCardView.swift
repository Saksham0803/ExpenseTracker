//
//  CreditCardView.swift
//  Expense Tracker
//
//  Dashboard for credit-card payments: what you charged, what counts as your
//  own spending, what's still owed to you, and what you've recovered.
//

import SwiftUI

struct CreditCardView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    @State private var showingLogPayment = false
    @State private var showingGroups = false
    @State private var showingSettings = false
    @State private var showAllTime = false
    @State private var anchorDate = Date()
    @State private var editingPayment: Expense?

    private var cycle: ExpenseManager.BillingCycle { expenseManager.cycle(containing: anchorDate) }

    private var payments: [Expense] {
        showAllTime ? expenseManager.creditCardExpenses : expenseManager.creditCardExpenses(in: cycle)
    }

    // Stats scoped to the current view (whole history or the selected cycle).
    private var charged: Double { showAllTime ? expenseManager.creditCardCharged : expenseManager.charged(in: cycle) }
    private var myNet: Double { showAllTime ? expenseManager.creditCardMyNet : expenseManager.myNet(in: cycle) }
    private var outstanding: Double { showAllTime ? expenseManager.creditCardOutstanding : expenseManager.outstanding(in: cycle) }
    private var recovered: Double { showAllTime ? expenseManager.creditCardRecovered : expenseManager.recovered(in: cycle) }

    var body: some View {
        NavigationView {
            Group {
                if expenseManager.creditCardExpenses.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            cycleHeader
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                            statsGrid
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }

                        if payments.isEmpty {
                            Section {
                                Text("No payments in this billing cycle.")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 12)
                            }
                        } else {
                            ForEach(payments) { payment in
                                Section {
                                    PaymentCardView(payment: payment)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                expenseManager.deleteExpense(payment)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            Button {
                                                editingPayment = payment
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                        }
                                        .contextMenu {
                                            Button {
                                                editingPayment = payment
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                expenseManager.deleteExpense(payment)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Credit Card")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        showingGroups = true
                    } label: {
                        Image(systemName: "person.3")
                    }
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingLogPayment = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingLogPayment) {
                ExpenseEditorView(presetMethod: .card, startSplitting: true)
            }
            .sheet(item: $editingPayment) { payment in
                ExpenseEditorView(editing: payment)
            }
            .sheet(isPresented: $showingGroups) {
                GroupsView()
            }
            .sheet(isPresented: $showingSettings) {
                billingSettings
            }
        }
    }

    private var cycleHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    anchorDate = expenseManager.cycle(offsetting: cycle, by: -1).start
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(showAllTime)

                Spacer()
                VStack(spacing: 2) {
                    Text(showAllTime ? "All time" : cycleTitle(cycle))
                        .font(.subheadline).fontWeight(.semibold)
                    Text(showAllTime ? "Every card payment" : "Billing cycle")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()

                Button {
                    anchorDate = expenseManager.cycle(offsetting: cycle, by: 1).start
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(showAllTime || cycle.start >= expenseManager.cycle(containing: Date()).start)
            }

            Button {
                withAnimation { showAllTime.toggle() }
                if !showAllTime { anchorDate = Date() }
            } label: {
                Text(showAllTime ? "View by billing cycle" : "View all time")
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var billingSettings: some View {
        NavigationView {
            Form {
                Section(header: Text("Billing cycle"), footer: Text("Your statement runs from this day of the month to the same day next month. For a 20-to-20 card, set 20.")) {
                    Stepper(value: $expenseManager.billingCycleDay, in: 1...28) {
                        HStack {
                            Text("Statement day")
                            Spacer()
                            Text("\(expenseManager.billingCycleDay)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Card Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingSettings = false }
                }
            }
        }
    }

    private func cycleTitle(_ cycle: ExpenseManager.BillingCycle) -> String {
        let cal = Calendar.current
        let lastDay = cal.date(byAdding: .day, value: -1, to: cycle.end) ?? cycle.end
        let start = DateFormatter()
        start.dateFormat = "d MMM"
        let end = DateFormatter()
        end.dateFormat = "d MMM yyyy"
        return "\(start.string(from: cycle.start)) – \(end.string(from: lastDay))"
    }

    private var statsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(title: "Charged to card", value: charged, color: .primary)
                StatTile(title: "Your spending", value: myNet, color: .blue)
            }
            HStack(spacing: 12) {
                StatTile(title: "Owed to you", value: outstanding, color: .orange)
                StatTile(title: "Recovered", value: recovered, color: .green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No card payments yet")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Tap + to log a payment you made on your credit card and split with others.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingLogPayment = true
            } label: {
                Label("Log a payment", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(formatCurrency(value))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}

struct PaymentCardView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    let payment: Expense

    private var split: SplitInfo? { payment.split }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: payment.category.icon)
                    .foregroundColor(payment.category.colorValue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(payment.title)
                        .font(.headline)
                    Text(payment.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCurrency(split?.totalAmount ?? payment.amount))
                        .font(.headline)
                    Label(payment.method.rawValue, systemImage: payment.method.icon)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let split {
                HStack(spacing: 16) {
                    if split.myShareIncluded {
                        miniStat("Your share", split.myShare, .blue)
                    }
                    miniStat("Owed", split.outstandingTotal, .orange)
                    miniStat("Recovered", split.settledTotal, .green)
                }

                Divider()

                ForEach(split.participants) { participant in
                    Button {
                        expenseManager.setSettled(!participant.isSettled, participantID: participant.id, in: payment)
                    } label: {
                        HStack {
                            Image(systemName: participant.isSettled ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(participant.isSettled ? .green : .secondary)
                            Text(participant.name)
                                .foregroundColor(.primary)
                                .strikethrough(participant.isSettled)
                            Spacer()
                            Text(formatCurrency(participant.amount))
                                .foregroundColor(participant.isSettled ? .secondary : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func miniStat(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(formatCurrency(value))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}

#Preview {
    CreditCardView()
        .environmentObject(ExpenseManager())
}

// MARK: - UPI + Cash tab

/// Recovery dashboard for split expenses paid via UPI or cash (no billing cycle).
struct CashUpiView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    @State private var showingAdd = false
    @State private var editingPayment: Expense?
    @State private var filter: MethodFilter = .all

    enum MethodFilter: String, CaseIterable {
        case all = "All"
        case upi = "UPI"
        case cash = "Cash"

        var methods: Set<PaymentMethod> {
            switch self {
            case .all: return [.upi, .cash]
            case .upi: return [.upi]
            case .cash: return [.cash]
            }
        }
    }

    private var payments: [Expense] { expenseManager.splitExpenses(methods: filter.methods) }

    var body: some View {
        NavigationView {
            Group {
                if expenseManager.splitExpenses(methods: [.upi, .cash]).isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            Picker("Method", selection: $filter) {
                                ForEach(MethodFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)

                            statsGrid
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }

                        if payments.isEmpty {
                            Section {
                                Text("No \(filter.rawValue.lowercased()) split payments yet.")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 12)
                            }
                        } else {
                            ForEach(payments) { payment in
                                Section {
                                    PaymentCardView(payment: payment)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                expenseManager.deleteExpense(payment)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            Button {
                                                editingPayment = payment
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                        }
                                        .contextMenu {
                                            Button {
                                                editingPayment = payment
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                expenseManager.deleteExpense(payment)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("UPI & Cash")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                ExpenseEditorView(presetMethod: filter == .cash ? .cash : .upi, startSplitting: true)
            }
            .sheet(item: $editingPayment) { payment in
                ExpenseEditorView(editing: payment)
            }
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(title: "Total paid", value: expenseManager.chargedTotal(payments), color: .primary)
                StatTile(title: "Your spending", value: expenseManager.myNetTotal(payments), color: .blue)
            }
            HStack(spacing: 12) {
                StatTile(title: "Owed to you", value: expenseManager.outstandingTotal(payments), color: .orange)
                StatTile(title: "Recovered", value: expenseManager.recoveredTotal(payments), color: .green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "indianrupeesign.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No UPI or cash splits yet")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Tap + to log a UPI or cash payment you split with others. Your share counts as spending; the rest is tracked as owed to you.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingAdd = true
            } label: {
                Label("Log a payment", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Cash & UPI") {
    CashUpiView()
        .environmentObject(ExpenseManager())
}
