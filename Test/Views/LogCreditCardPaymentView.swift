//
//  LogCreditCardPaymentView.swift
//  Expense Tracker
//
//  Log a credit-card payment split with other people. Your own share flows into
//  regular spending; everyone else's portion is tracked as owed back to you.
//

import SwiftUI

struct LogCreditCardPaymentView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager

    private struct EditableParticipant: Identifiable {
        let id = UUID()
        var name: String
        var contactIdentifier: String?
        var amountText: String = ""

        var amount: Double { Double(amountText) ?? 0 }
    }

    @State private var title: String = ""
    @State private var totalText: String = ""
    @State private var selectedCategory: ExpenseCategory = .food
    @State private var selectedDate: Date = Date()
    @State private var notes: String = ""
    @State private var myShareIncluded: Bool = true
    @State private var participants: [EditableParticipant] = []

    @State private var showingContactPicker = false

    private var total: Double { Double(totalText) ?? 0 }
    private var participantsTotal: Double { participants.reduce(0) { $0 + $1.amount } }
    private var myShare: Double { max(0, total - participantsTotal) }
    private var unassigned: Double { total - participantsTotal }

    private var isValid: Bool {
        guard !title.isEmpty, total > 0 else { return false }
        guard participants.allSatisfy({ !$0.name.isEmpty && $0.amount > 0 }) else { return false }
        guard participantsTotal <= total + 0.001 else { return false }
        // If your share isn't included, everything must be recovered from others.
        if !myShareIncluded && abs(unassigned) > 0.001 { return false }
        return true
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Payment")) {
                    TextField("What was it for?", text: $title)

                    HStack {
                        Text("Total on card")
                        Spacer()
                        TextField("0", text: $totalText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
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

                Section(header: Text("Split with"), footer: splitFooter) {
                    ForEach($participants) { $participant in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(participant.name)
                                if participant.contactIdentifier != nil {
                                    Text("Contact")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            TextField("0", text: $participant.amountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                    .onDelete { participants.remove(atOffsets: $0) }

                    Button {
                        showingContactPicker = true
                    } label: {
                        Label("Add from contacts", systemImage: "person.crop.circle.badge.plus")
                    }

                    Button {
                        participants.append(EditableParticipant(name: "Person \(participants.count + 1)"))
                    } label: {
                        Label("Add manually", systemImage: "plus.circle")
                    }
                }

                Section {
                    Toggle("Include my share", isOn: $myShareIncluded)
                    if myShareIncluded {
                        summaryRow(label: "Your share (counts as spending)", value: myShare, color: .primary)
                    }
                    summaryRow(label: "Owed to you", value: participantsTotal, color: .orange)
                    if unassigned > 0.001 && !myShareIncluded {
                        summaryRow(label: "Unassigned — assign to people", value: unassigned, color: .red)
                    }
                }

                Section(header: Text("Notes")) {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Log Card Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPicker { picked in
                    participants.append(EditableParticipant(name: picked.name, contactIdentifier: picked.identifier))
                }
            }
        }
    }

    private var splitFooter: some View {
        Text("Enter what each person owes you. Anything left over is your own share.")
    }

    private func summaryRow(label: String, value: Double, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(formatCurrency(value))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }

    private func save() {
        guard isValid else { return }

        // Store date in IST, matching AddExpenseView.
        let istTimeZone = TimeZone(identifier: "Asia/Kolkata")!
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: istTimeZone, from: selectedDate)
        let istDate = calendar.date(from: components) ?? selectedDate

        let splitParticipants = participants.map {
            SplitParticipant(name: $0.name, contactIdentifier: $0.contactIdentifier, amount: $0.amount)
        }
        let split = SplitInfo(totalAmount: total, myShareIncluded: myShareIncluded, participants: splitParticipants)

        let expense = Expense(
            title: title,
            amount: myShareIncluded ? myShare : 0,
            category: selectedCategory,
            type: .expense,
            date: istDate,
            notes: notes,
            split: split
        )
        expenseManager.addExpense(expense)
        dismiss()
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}

#Preview {
    LogCreditCardPaymentView()
        .environmentObject(ExpenseManager())
}
