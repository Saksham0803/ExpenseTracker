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

    private var payments: [Expense] { expenseManager.creditCardExpenses }

    var body: some View {
        NavigationView {
            Group {
                if payments.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            statsGrid
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }

                        ForEach(payments) { payment in
                            Section {
                                PaymentCardView(payment: payment)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Credit Card")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingLogPayment = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingLogPayment) {
                LogCreditCardPaymentView()
            }
        }
    }

    private var statsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(title: "Charged to card", value: expenseManager.creditCardCharged, color: .primary)
                StatTile(title: "Your spending", value: expenseManager.creditCardMyNet, color: .blue)
            }
            HStack(spacing: 12) {
                StatTile(title: "Owed to you", value: expenseManager.creditCardOutstanding, color: .orange)
                StatTile(title: "Recovered", value: expenseManager.creditCardRecovered, color: .green)
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
                    Text("on card")
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
