//
//  ReviewInboxView.swift
//  Expense Tracker
//
//  Auto-captured transactions that still need a note/category. They already
//  count in your totals — this is just the quick-annotate queue.
//

import SwiftUI

struct ReviewInboxView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager
    @State private var annotating: Expense?
    @State private var matchingPaymentID: UUID?

    private var items: [Expense] { expenseManager.needsReviewExpenses }
    private var received: [ReceivedPayment] { expenseManager.receivedPayments.sorted { $0.date > $1.date } }

    var body: some View {
        NavigationView {
            Group {
                if items.isEmpty && received.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 60)).foregroundColor(.green)
                        Text("All caught up").font(.title2).foregroundColor(.secondary)
                        Text("Auto-logged transactions that need a note, and money you've received, will show up here.")
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                } else {
                    List {
                        if !received.isEmpty {
                            Section(header: Text("Money received"),
                                    footer: Text("Match each payment to who paid you back. It never counts as spending.")) {
                                ForEach(received) { payment in
                                    Button { matchingPaymentID = payment.id } label: { receivedRow(payment) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        if !items.isEmpty {
                            Section(header: Text("Needs a note")) {
                                ForEach(items) { exp in
                                    Button { annotating = exp } label: { row(exp) }
                                        .buttonStyle(.plain)
                                        .swipeActions {
                                            Button { expenseManager.markReviewed(exp.id) } label: {
                                                Label("Looks good", systemImage: "checkmark")
                                            }
                                            .tint(.green)
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Needs Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $annotating) { exp in
                ReviewAnnotateView(expense: exp)
            }
            .sheet(isPresented: Binding(get: { matchingPaymentID != nil },
                                        set: { if !$0 { matchingPaymentID = nil } })) {
                if let id = matchingPaymentID {
                    MatchPaymentView(paymentID: id)
                }
            }
        }
    }

    private func receivedRow(_ payment: ReceivedPayment) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.2)).frame(width: 44, height: 44)
                Image(systemName: "arrow.down.circle.fill").foregroundColor(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("From \(payment.sender)").font(.headline)
                Text("Tap to match who paid you back").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text("+" + NotificationManager.currency(payment.amount))
                .font(.headline).foregroundColor(.green)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func row(_ exp: Expense) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(exp.category.colorValue.opacity(0.2)).frame(width: 44, height: 44)
                Image(systemName: exp.category.icon).foregroundColor(exp.category.colorValue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(exp.title).font(.headline)
                Text("Tap to add a note or category").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(NotificationManager.currency(exp.amount)).font(.headline)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Quick-annotate one transaction — pick a category and dictate/type a note.
struct ReviewAnnotateView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager
    @StateObject private var speech = SpeechRecognizer()

    let expense: Expense
    @State private var category: ExpenseCategory
    @State private var notes: String

    init(expense: Expense) {
        self.expense = expense
        _category = State(initialValue: expense.category)
        _notes = State(initialValue: expense.notes)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text(expense.title).font(.headline)
                        Spacer()
                        Text(NotificationManager.currency(expense.amount)).font(.headline)
                    }
                    Text(expense.date, style: .date).font(.caption).foregroundColor(.secondary)
                }

                Section(header: Text("Category")) {
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { c in
                            Label(c.rawValue, systemImage: c.icon).tag(c)
                        }
                    }
                }

                Section(header: Text("Note")) {
                    TextField("Add a note", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                    Button {
                        speech.toggle()
                    } label: {
                        Label(speech.isRecording ? "Stop dictation" : "Dictate note",
                              systemImage: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                            .foregroundColor(speech.isRecording ? .red : .accentColor)
                    }
                    if let message = speech.errorMessage {
                        Text(message)
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { speech.stop() }
            .onChange(of: speech.transcript) { newValue in
                if !newValue.isEmpty { notes = newValue }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Save") { save() } }
            }
        }
    }

    private func save() {
        speech.stop()
        var updated = expense
        updated.category = category
        updated.notes = notes
        updated.needsReview = false
        expenseManager.updateExpense(updated)
        dismiss()
    }
}

/// Match one received payment to the share(s) it pays back, or mark it as a
/// refund / not an expense. Nothing changes until the user taps.
struct MatchPaymentView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager
    let paymentID: UUID

    private var payment: ReceivedPayment? {
        expenseManager.receivedPayments.first { $0.id == paymentID }
    }

    var body: some View {
        NavigationView {
            Group {
                if let payment {
                    let matches = expenseManager.matches(for: payment)
                    List {
                        Section {
                            HStack {
                                Text("From \(payment.sender)").font(.headline)
                                Spacer()
                                Text("+" + NotificationManager.currency(payment.amount))
                                    .font(.headline).foregroundColor(.green)
                            }
                            if !payment.rawMessage.isEmpty {
                                Text(payment.rawMessage).font(.caption).foregroundColor(.secondary)
                            }
                        }

                        Section(header: Text("Who paid you back?"),
                                footer: Text("A smaller payment leaves the rest owing. Anything extra stays here to match to another share.")) {
                            if matches.isEmpty {
                                Text("Nobody owes you anything right now.").foregroundColor(.secondary)
                            }
                            ForEach(matches) { match in
                                Button {
                                    expenseManager.apply(paymentID, to: match.participantID, in: match.expenseID)
                                } label: {
                                    matchRow(match, paymentAmount: payment.amount)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Section(header: Text("Not a payback?")) {
                            Button {
                                expenseManager.markAsRefund(paymentID)
                                dismiss()
                            } label: {
                                Label("It's a refund", systemImage: "arrow.uturn.backward.circle")
                            }
                            Button(role: .destructive) {
                                expenseManager.dismissReceivedPayment(paymentID)
                                dismiss()
                            } label: {
                                Label("Not an expense", systemImage: "xmark.circle")
                            }
                        }
                    }
                } else {
                    // Fully matched — nothing left to allocate.
                    Color.clear.onAppear { dismiss() }
                }
            }
            .navigationTitle("Money Received")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func matchRow(_ match: ShareMatch, paymentAmount: Double) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(match.personName).font(.headline)
                Text("for \(match.expenseTitle)").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    if match.nameMatches { badge("Name matches") }
                    if match.amountMatches { badge("Exact amount") }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("owes " + NotificationManager.currency(match.remaining)).font(.subheadline)
                if paymentAmount < match.remaining - 0.009 {
                    Text(NotificationManager.currency(match.remaining - paymentAmount) + " left after")
                        .font(.caption2).foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.green.opacity(0.15)))
            .foregroundColor(.green)
    }
}

#Preview {
    ReviewInboxView().environmentObject(ExpenseManager())
}
