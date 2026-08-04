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
        /// True once the user types an explicit amount for this person; such
        /// amounts are held fixed while the rest split the remainder equally.
        var isManual: Bool = false

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
    @State private var showingGroups = false
    @State private var showingSaveGroup = false
    @State private var newGroupName = ""

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
                                Text(participant.isManual ? "edited" : "split equally")
                                    .font(.caption2)
                                    .foregroundColor(participant.isManual ? .orange : .secondary)
                            }
                            Spacer()
                            TextField("0", text: Binding(
                                get: { participant.amountText },
                                set: { newValue in
                                    $participant.wrappedValue.amountText = newValue
                                    $participant.wrappedValue.isManual = !newValue.isEmpty
                                    redistribute()
                                }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        }
                    }
                    .onDelete { offsets in
                        participants.remove(atOffsets: offsets)
                        redistribute()
                    }

                    Button {
                        showingContactPicker = true
                    } label: {
                        Label("Add from contacts", systemImage: "person.crop.circle.badge.plus")
                    }

                    Button {
                        participants.append(EditableParticipant(name: "Person \(participants.count + 1)"))
                        redistribute()
                    } label: {
                        Label("Add manually", systemImage: "plus.circle")
                    }

                    Menu {
                        if expenseManager.groups.isEmpty {
                            Text("No saved groups")
                        } else {
                            ForEach(expenseManager.groups) { group in
                                Button {
                                    addMembers(from: group)
                                } label: {
                                    Label("\(group.name) (\(group.members.count))", systemImage: "person.3.fill")
                                }
                            }
                        }
                        Divider()
                        Button {
                            showingGroups = true
                        } label: {
                            Label("Manage groups…", systemImage: "gearshape")
                        }
                    } label: {
                        Label("Add from group", systemImage: "person.3")
                    }

                    if !participants.isEmpty {
                        Button {
                            newGroupName = ""
                            showingSaveGroup = true
                        } label: {
                            Label("Save these as a group", systemImage: "square.and.arrow.down")
                        }
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
            .onChange(of: totalText) { _ in redistribute() }
            .onChange(of: myShareIncluded) { _ in redistribute() }
            .sheet(isPresented: $showingContactPicker) {
                ContactPicker { picked in
                    participants.append(EditableParticipant(name: picked.name, contactIdentifier: picked.identifier))
                    redistribute()
                }
            }
            .sheet(isPresented: $showingGroups) {
                GroupsView()
            }
            .alert("Save as group", isPresented: $showingSaveGroup) {
                TextField("Group name", text: $newGroupName)
                Button("Save") { saveCurrentAsGroup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save these \(participants.count) people so you can add them in one tap next time.")
            }
        }
    }

    /// Add a saved group's members, skipping anyone already in the list.
    private func addMembers(from group: PersonGroup) {
        for member in group.members {
            let alreadyThere = participants.contains { existing in
                if let id = member.contactIdentifier, let eid = existing.contactIdentifier {
                    return id == eid
                }
                return existing.name.caseInsensitiveCompare(member.name) == .orderedSame
            }
            if !alreadyThere {
                participants.append(EditableParticipant(name: member.name, contactIdentifier: member.contactIdentifier))
            }
        }
        redistribute()
    }

    /// Split the total equally across everyone who hasn't been given an explicit
    /// amount. People with a manually entered amount keep it; the remainder is
    /// divided evenly among the rest (and your own share, when included).
    private func redistribute() {
        let autoIndices = participants.indices.filter { !participants[$0].isManual }
        guard !autoIndices.isEmpty else { return }
        guard total > 0 else { return }

        let manualTotal = participants.filter { $0.isManual }.reduce(0) { $0 + $1.amount }
        let remaining = max(0, total - manualTotal)
        // Your own share counts as one more equal head when it's included.
        let heads = autoIndices.count + (myShareIncluded ? 1 : 0)
        guard heads > 0 else { return }

        func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
        let perHead = round2(remaining / Double(heads))
        var amounts = autoIndices.map { _ in perHead }

        // When your share isn't included, the participants must cover the whole
        // remainder — give the rounding residual to the last person so it's exact.
        if !myShareIncluded, let last = amounts.indices.last {
            let residual = round2(remaining - amounts.reduce(0, +))
            amounts[last] = round2(amounts[last] + residual)
        }

        for (k, i) in autoIndices.enumerated() {
            participants[i].amountText = formatAmountText(amounts[k])
        }
    }

    private func formatAmountText(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func saveCurrentAsGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !participants.isEmpty else { return }
        let members = participants.map { GroupMember(name: $0.name, contactIdentifier: $0.contactIdentifier) }
        expenseManager.addGroup(PersonGroup(name: trimmed, members: members))
    }

    private var splitFooter: some View {
        Text("Everyone splits the total equally by default. Type an amount for anyone to fix their share — the rest re-split what's left.")
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
