//
//  TripsView.swift
//  Expense Tracker
//
//  Group-trip ledger with Splitwise-style settle up.
//

import SwiftUI

private func money(_ amount: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = Locale.current
    return f.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
}

// MARK: - Trips list (tab)

struct TripsView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    @State private var showingCreate = false

    var body: some View {
        NavigationView {
            Group {
                if expenseManager.trips.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(expenseManager.trips.sorted { $0.startDate > $1.startDate }) { trip in
                            NavigationLink {
                                TripDetailView(tripID: trip.id)
                            } label: {
                                TripRow(trip: trip)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingCreate) {
                TripEditorView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No trips yet")
                .font(.title2).foregroundColor(.secondary)
            Text("Create a trip, add who's coming, and log expenses as anyone pays. At the end, settle up in the fewest transfers.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button { showingCreate = true } label: {
                Label("Create a trip", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct TripRow: View {
    let trip: Trip
    var body: some View {
        HStack {
            Image(systemName: "suitcase.fill")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name).font(.headline)
                Text("\(trip.members.count) people • \(trip.expenses.count) expenses")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(money(trip.total)).font(.headline)
                if trip.isClosed {
                    Text("Settled").font(.caption2).foregroundColor(.green)
                }
            }
        }
    }
}

// MARK: - Trip detail

struct TripDetailView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    let tripID: UUID

    @State private var section: Section = .expenses
    @State private var showingAddExpense = false
    @State private var showingEditTrip = false
    @State private var showingImport = false
    @State private var editingExpense: TripExpense?

    enum Section: String, CaseIterable { case expenses = "Expenses", balances = "Balances", settle = "Settle Up" }

    private var trip: Trip? { expenseManager.trips.first { $0.id == tripID } }

    var body: some View {
        Group {
            if let trip {
                List {
                    Picker("View", selection: $section) {
                        ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    switch section {
                    case .expenses: expensesSection(trip)
                    case .balances: balancesSection(trip)
                    case .settle: settleSection(trip)
                    }
                }
                .navigationTitle(trip.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button { showingAddExpense = true } label: { Label("Add expense", systemImage: "plus") }
                            Button { showingImport = true } label: { Label("Import from my expenses", systemImage: "square.and.arrow.down") }
                            Button { showingEditTrip = true } label: { Label("Edit trip", systemImage: "pencil") }
                            Button {
                                var t = trip; t.isClosed.toggle(); expenseManager.updateTrip(t)
                            } label: {
                                Label(trip.isClosed ? "Reopen trip" : "End & settle trip",
                                      systemImage: trip.isClosed ? "lock.open" : "checkmark.seal")
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .sheet(isPresented: $showingAddExpense) {
                    TripExpenseEditorView(trip: trip)
                }
                .sheet(isPresented: $showingEditTrip) {
                    TripEditorView(editing: trip)
                }
                .sheet(item: $editingExpense) { exp in
                    TripExpenseEditorView(trip: trip, editing: exp)
                }
                .sheet(isPresented: $showingImport) {
                    TripImportExpensesView(trip: trip)
                }
            } else {
                Text("Trip not found").foregroundColor(.secondary)
            }
        }
    }

    // Expenses list
    @ViewBuilder private func expensesSection(_ trip: Trip) -> some View {
        SwiftUI.Section {
            HStack {
                stat("Total", trip.total, .primary)
                if let me = trip.myMember {
                    stat("Your share", trip.share(of: me.id), .blue)
                    stat("You paid", trip.paid(by: me.id), .orange)
                }
            }
            .listRowBackground(Color.clear)
        }

        if trip.expenses.isEmpty {
            Text("No expenses yet. Tap ••• → Add expense.")
                .foregroundColor(.secondary)
        } else {
            SwiftUI.Section {
                ForEach(trip.expenses.sorted { $0.date > $1.date }) { exp in
                    Button { editingExpense = exp } label: { tripExpenseRow(trip, exp) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                expenseManager.deleteTripExpense(exp.id, in: trip.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        }
    }

    private func tripExpenseRow(_ trip: Trip, _ exp: TripExpense) -> some View {
        HStack {
            Image(systemName: exp.category.icon).foregroundColor(exp.category.colorValue)
            VStack(alignment: .leading, spacing: 2) {
                Text(exp.title).font(.headline)
                Text("Paid by \(trip.member(exp.payerID)?.name ?? "?") • \(exp.date, style: .date)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(money(exp.amount)).font(.headline)
        }
    }

    // Balances per member
    @ViewBuilder private func balancesSection(_ trip: Trip) -> some View {
        SwiftUI.Section(footer: Text("Net is what each person paid minus their share. Positive means the group owes them.")) {
            ForEach(trip.members) { m in
                let net = trip.net(of: m.id)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.isMe ? "You" : m.name).font(.headline)
                        Text("paid \(money(trip.paid(by: m.id))) • share \(money(trip.share(of: m.id)))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text((net >= 0 ? "+" : "") + money(net))
                        .fontWeight(.semibold)
                        .foregroundColor(abs(net) < 0.01 ? .secondary : (net > 0 ? .green : .red))
                }
            }
        }

        if !trip.categoryBreakdown().isEmpty {
            SwiftUI.Section(header: Text("By category")) {
                ForEach(trip.categoryBreakdown(), id: \.category) { item in
                    HStack {
                        Image(systemName: item.category.icon).foregroundColor(item.category.colorValue)
                        Text(item.category.rawValue)
                        Spacer()
                        Text(money(item.amount)).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // Settlement
    @ViewBuilder private func settleSection(_ trip: Trip) -> some View {
        let settlements = trip.settlements()
        if settlements.isEmpty {
            SwiftUI.Section {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("All settled up — nobody owes anything.")
                }
            }
        } else {
            SwiftUI.Section(footer: Text("The fewest transfers that clear every balance.")) {
                ForEach(settlements) { s in
                    HStack {
                        Text(s.from.isMe ? "You" : s.from.name).fontWeight(.medium)
                        Image(systemName: "arrow.right").font(.caption).foregroundColor(.secondary)
                        Text(s.to.isMe ? "You" : s.to.name).fontWeight(.medium)
                        Spacer()
                        Text(money(s.amount)).fontWeight(.semibold).foregroundColor(.blue)
                    }
                }
            }
        }
    }

    private func stat(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(money(value)).font(.subheadline).fontWeight(.bold).foregroundColor(color)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Create / edit trip

struct TripEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager

    let editing: Trip?
    init(editing: Trip? = nil) { self.editing = editing }

    @State private var name = ""
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var members: [TripMember] = []
    @State private var didPrefill = false
    @State private var showingContactPicker = false

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && members.count >= 2 }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Trip")) {
                    TextField("Trip name (e.g. Goa)", text: $name)
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    Toggle("Has end date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section(header: Text("Who's on the trip"), footer: Text("You're included automatically. Add everyone splitting costs.")) {
                    ForEach(members) { m in
                        HStack {
                            Image(systemName: m.isMe ? "person.crop.circle.fill" : "person.crop.circle")
                                .foregroundColor(m.isMe ? .accentColor : .secondary)
                            Text(m.isMe ? "You" : m.name)
                            Spacer()
                        }
                    }
                    .onDelete { offsets in
                        // Never remove yourself.
                        let removable = offsets.filter { !members[$0].isMe }
                        members.remove(atOffsets: IndexSet(removable))
                    }

                    Button { showingContactPicker = true } label: {
                        Label("Add from contacts", systemImage: "person.crop.circle.badge.plus")
                    }
                    Button {
                        members.append(TripMember(name: "Person \(members.count)"))
                    } label: {
                        Label("Add manually", systemImage: "plus.circle")
                    }
                    if !expenseManager.groups.isEmpty {
                        Menu {
                            ForEach(expenseManager.groups) { group in
                                Button {
                                    addGroup(group)
                                } label: { Label("\(group.name) (\(group.members.count))", systemImage: "person.3.fill") }
                            }
                        } label: { Label("Add from group", systemImage: "person.3") }
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Save") { save() }.disabled(!isValid) }
            }
            .onAppear(perform: prefill)
            .sheet(isPresented: $showingContactPicker) {
                ContactPicker { picked in
                    if !members.contains(where: { $0.contactIdentifier == picked.identifier }) {
                        members.append(TripMember(name: picked.name, contactIdentifier: picked.identifier))
                    }
                }
            }
        }
    }

    private func addGroup(_ group: PersonGroup) {
        for gm in group.members where !members.contains(where: { ($0.contactIdentifier != nil && $0.contactIdentifier == gm.contactIdentifier) || $0.name.caseInsensitiveCompare(gm.name) == .orderedSame }) {
            members.append(TripMember(name: gm.name, contactIdentifier: gm.contactIdentifier))
        }
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        if let editing {
            name = editing.name
            startDate = editing.startDate
            if let e = editing.endDate { hasEndDate = true; endDate = e }
            members = editing.members
        } else {
            members = [TripMember(name: "You", isMe: true)]
        }
    }

    private func save() {
        guard isValid else { return }
        let trip = Trip(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            members: members,
            expenses: editing?.expenses ?? [],
            isClosed: editing?.isClosed ?? false
        )
        if editing == nil { expenseManager.addTrip(trip) } else { expenseManager.updateTrip(trip) }
        dismiss()
    }
}

// MARK: - Add / edit a trip expense

struct TripExpenseEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager

    let trip: Trip
    let editing: TripExpense?
    init(trip: Trip, editing: TripExpense? = nil) { self.trip = trip; self.editing = editing }

    private struct EditableShare: Identifiable {
        var id: UUID { memberID }
        let memberID: UUID
        let name: String
        var included: Bool
        var amountText: String
        var isManual: Bool
        var amount: Double { Double(amountText) ?? 0 }
    }

    @State private var title = ""
    @State private var amountText = ""
    @State private var selectedCategory: ExpenseCategory = .food
    @State private var selectedDate = Date()
    @State private var notes = ""
    @State private var payerID = UUID()
    @State private var rows: [EditableShare] = []
    @State private var didPrefill = false

    private var amount: Double { Double(amountText) ?? 0 }
    private var includedTotal: Double { rows.filter { $0.included }.reduce(0) { $0 + $1.amount } }

    private var isValid: Bool {
        guard !title.isEmpty, amount > 0 else { return false }
        guard rows.contains(where: { $0.included }) else { return false }
        return abs(includedTotal - amount) < 0.02
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Expense")) {
                    TextField("What was it for?", text: $title)
                    HStack {
                        Text("Amount"); Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { c in
                            Label(c.rawValue, systemImage: c.icon).tag(c)
                        }
                    }
                    Picker("Paid by", selection: $payerID) {
                        ForEach(trip.members) { m in
                            Text(m.isMe ? "You" : m.name).tag(m.id)
                        }
                    }
                    DatePicker("Date & Time", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section(header: Text("Split between"), footer: Text("Included people split the amount equally by default. Type an amount to fix someone's share; the rest re-split.")) {
                    ForEach($rows) { $row in
                        HStack {
                            Button {
                                $row.wrappedValue.included.toggle()
                                $row.wrappedValue.isManual = false
                                redistribute()
                            } label: {
                                Image(systemName: row.included ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(row.included ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)

                            Text(row.name)
                            Spacer()
                            if row.included {
                                TextField("0", text: Binding(
                                    get: { row.amountText },
                                    set: { newVal in
                                        $row.wrappedValue.amountText = newVal
                                        $row.wrappedValue.isManual = !newVal.isEmpty
                                        redistribute()
                                    }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            } else {
                                Text("—").foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Assigned"); Spacer()
                        Text(money(includedTotal))
                            .foregroundColor(abs(includedTotal - amount) < 0.02 ? .green : .red)
                    }
                }

                Section(header: Text("Notes")) {
                    TextField("Optional notes", text: $notes, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle(editing == nil ? "Add Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Save") { save() }.disabled(!isValid) }
            }
            .onAppear(perform: prefill)
            .onChange(of: amountText) { _ in redistribute() }
        }
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }

    private func redistribute() {
        guard amount > 0 else { return }
        let includedIdx = rows.indices.filter { rows[$0].included }
        let autoIdx = includedIdx.filter { !rows[$0].isManual }
        guard !autoIdx.isEmpty else { return }
        let manualSum = includedIdx.filter { rows[$0].isManual }.reduce(0.0) { $0 + rows[$1].amount }
        let remaining = max(0, amount - manualSum)
        func r2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
        let per = r2(remaining / Double(autoIdx.count))
        var vals = autoIdx.map { _ in per }
        if let last = vals.indices.last {
            let resid = r2(remaining - vals.reduce(0, +))
            vals[last] = r2(vals[last] + resid)
        }
        for (k, i) in autoIdx.enumerated() { rows[i].amountText = fmt(vals[k]) }
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        if let editing {
            title = editing.title
            amountText = fmt(editing.amount)
            selectedCategory = editing.category
            selectedDate = editing.date
            notes = editing.notes
            payerID = editing.payerID
            rows = trip.members.map { m in
                let s = editing.share(of: m.id)
                let included = editing.shares.contains { $0.memberID == m.id }
                return EditableShare(memberID: m.id, name: m.isMe ? "You" : m.name,
                                     included: included, amountText: included ? fmt(s) : "", isManual: included)
            }
        } else {
            payerID = trip.myMember?.id ?? trip.members.first?.id ?? UUID()
            rows = trip.members.map { m in
                EditableShare(memberID: m.id, name: m.isMe ? "You" : m.name, included: true, amountText: "", isManual: false)
            }
        }
    }

    private func save() {
        guard isValid else { return }
        let istTimeZone = TimeZone(identifier: "Asia/Kolkata")!
        let calendar = Calendar.current
        let comps = calendar.dateComponents(in: istTimeZone, from: selectedDate)
        let istDate = calendar.date(from: comps) ?? selectedDate

        let shares = rows.filter { $0.included && $0.amount > 0 }
            .map { TripShare(memberID: $0.memberID, amount: $0.amount) }

        let expense = TripExpense(
            id: editing?.id ?? UUID(),
            title: title,
            amount: amount,
            category: selectedCategory,
            date: istDate,
            payerID: payerID,
            shares: shares,
            notes: notes
        )
        expenseManager.upsertTripExpense(expense, in: trip.id)
        dismiss()
    }
}

// MARK: - Import existing personal expenses into a trip

struct TripImportExpensesView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager

    let trip: Trip
    @State private var selected: Set<UUID> = []

    /// Plain personal expenses (not refunds, not already split, not trip-derived).
    private var eligible: [Expense] {
        expenseManager.expenses
            .filter { $0.type == .expense && $0.split == nil && !$0.isTripContribution }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationView {
            Group {
                if eligible.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray").font(.system(size: 50)).foregroundColor(.gray)
                        Text("No plain expenses to import").foregroundColor(.secondary)
                        Text("Only simple, non-split expenses can be moved into a trip.")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                } else {
                    List {
                        Section(footer: Text("Selected expenses move into “\(trip.name)”, split equally among all \(trip.members.count) members and paid by you. The originals are removed — only your share stays in your personal totals.")) {
                            ForEach(eligible) { exp in
                                Button {
                                    if selected.contains(exp.id) { selected.remove(exp.id) } else { selected.insert(exp.id) }
                                } label: {
                                    HStack {
                                        Image(systemName: selected.contains(exp.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selected.contains(exp.id) ? .accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(exp.title).foregroundColor(.primary)
                                            Text("\(exp.category.rawValue) • \(exp.date, style: .date)")
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(money(exp.amount)).foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import (\(selected.count))") { importSelected() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func importSelected() {
        let toImport = eligible.filter { selected.contains($0.id) }
        for exp in toImport {
            let shares = equalShares(of: exp.amount, among: trip.members)
            let te = TripExpense(
                title: exp.title,
                amount: exp.amount,
                category: exp.category,
                date: exp.date,
                payerID: trip.myMember?.id ?? trip.members.first?.id ?? UUID(),
                shares: shares,
                notes: exp.notes
            )
            expenseManager.upsertTripExpense(te, in: trip.id)
            expenseManager.deleteExpense(exp)
        }
        dismiss()
    }

    /// Split an amount equally across members, last one absorbing the rounding residual.
    private func equalShares(of amount: Double, among members: [TripMember]) -> [TripShare] {
        guard !members.isEmpty else { return [] }
        func r2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
        let per = r2(amount / Double(members.count))
        var shares = members.map { TripShare(memberID: $0.id, amount: per) }
        let residual = r2(amount - per * Double(members.count))
        if let last = shares.indices.last { shares[last].amount = r2(shares[last].amount + residual) }
        return shares
    }
}

#Preview {
    TripsView().environmentObject(ExpenseManager())
}
