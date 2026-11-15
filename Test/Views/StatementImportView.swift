//
//  StatementImportView.swift
//  Expense Tracker
//
//  Log past transactions from a downloaded bank / card statement. Every row is
//  shown first: duplicates of what's already logged are marked and unticked,
//  each row's payment method can be changed, and a spend can go straight into
//  the usual split editor.
//

import SwiftUI
import UniformTypeIdentifiers

struct StatementImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager

    @State private var source: StatementSource = .bank
    @State private var showingPicker = false
    @State private var fileURL: URL?
    @State private var needsPassword = false
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var rows: [StatementRow] = []
    @State private var splitting: Expense?
    @State private var renaming: StatementRow?
    @State private var splitCount = 0
    @State private var showingDone = false
    @State private var lastImport = (logged: 0, credits: 0)
    /// Last 4 digits of the statement's account / card, saved on every row.
    @State private var account = ""

    private var selected: [StatementRow] { rows.filter(\.include) }

    /// Rows tagged with the account shown above (as read from the statement or typed).
    private func withAccount(_ list: [StatementRow]) -> [StatementRow] {
        let digits = String(account.filter(\.isNumber).suffix(4))
        return list.map { var row = $0; row.account = digits.isEmpty ? nil : digits; return row }
    }

    var body: some View {
        NavigationView {
            List {
                if rows.isEmpty {
                    setupSections
                } else {
                    summarySection
                    Section {
                        ForEach($rows) { $row in rowView($row) }
                    }
                }
            }
            .navigationTitle("Import Statement")
            .navigationBarTitleDisplayMode(.inline)
            // Don't leave a copy of the statement behind in the app's temp folder.
            .onDisappear { if let fileURL { try? FileManager.default.removeItem(at: fileURL) } }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if !rows.isEmpty {
                    Button { importSelected() } label: {
                        Text("Import \(selected.count) transaction\(selected.count == 1 ? "" : "s")")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selected.isEmpty ? Color.gray : Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(selected.isEmpty)
                    .padding()
                    .background(.bar)
                }
            }
            .fileImporter(isPresented: $showingPicker,
                          allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .pdf]) { result in
                pickedFile(result)
            }
            .sheet(item: $splitting) { expense in
                ExpenseEditorView(editing: expense, startSplitting: true)
            }
            .sheet(item: $renaming) { row in
                PayeeEditView(row: row, sameCount: rows.filter { samePayee($0, row) }.count) { name, category, own, notSpending in
                    for i in rows.indices where samePayee(rows[i], row) {
                        rows[i].merchant = name
                        rows[i].category = category
                        if let notSpending { rows[i].notSpending = notSpending }
                        guard let own else { continue }   // switch untouched: leave flags as they are
                        if own, rows[i].flag == nil || rows[i].flag == .selfTransfer {
                            rows[i].flag = .selfTransfer
                            rows[i].include = false
                        } else if !own, rows[i].flag == .selfTransfer {
                            rows[i].flag = nil
                            rows[i].include = true
                        }
                    }
                    MerchantNamer.learn(row.sourceKey, name: name, category: category, ownAccount: own, notSpending: notSpending)
                }
            }
            .alert("Imported", isPresented: $showingDone) {
                Button("OK") { dismiss() }
            } message: {
                Text(doneMessage)
            }
        }
    }

    // MARK: - Choose file

    @ViewBuilder private var setupSections: some View {
        Section(header: Text("Statement from"),
                footer: Text("Card statements log as Card. Bank statements log as UPI, with ATM withdrawals as Cash — you can change any row before importing.")) {
            Picker("Statement from", selection: $source) {
                ForEach(StatementSource.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }

        Section(footer: Text("Download it from net banking or your card's website. CSV works best; PDF works if it isn't a scanned image. For Excel files, export as CSV first.")) {
            Button { showingPicker = true } label: {
                Label("Choose statement file", systemImage: "doc.text.magnifyingglass")
            }
        }

        if needsPassword {
            Section(header: Text("This PDF is locked"),
                    footer: Text("Banks usually use your date of birth or customer ID. It's only used to open this file and isn't saved.")) {
                SecureField("PDF password", text: $password)
                    .textContentType(.password)
                Button("Unlock") { load() }.disabled(password.isEmpty)
            }
        }

        if let errorMessage {
            Section { Text(errorMessage).foregroundColor(.red) }
        }
    }

    private func pickedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        // Copy it out of the picker's sandbox so a password retry can reopen it.
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        do {
            try FileManager.default.copyItem(at: url, to: copy)
            fileURL = copy
            needsPassword = false
            password = ""
            load()
        } catch {
            errorMessage = StatementError.unreadable.localizedDescription
        }
    }

    private func load() {
        guard let fileURL else { return }
        do {
            var parsed = try StatementParser().parse(url: fileURL, source: source, password: needsPassword ? password : nil)
            expenseManager.markDuplicates(&parsed)
            rows = parsed.sorted { $0.date > $1.date }
            account = parsed.first?.account ?? ""
            needsPassword = false
            errorMessage = nil
        } catch StatementError.locked {
            needsPassword = true
            errorMessage = nil
        } catch {
            if case StatementError.wrongPassword = error { needsPassword = true }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Review rows

    private var summarySection: some View {
        let duplicates = rows.filter { $0.flag == .duplicate }.count
        let billPayments = rows.filter { $0.flag == .cardBillPayment }.count
        let ownTransfers = rows.filter { $0.flag == .selfTransfer }.count
        let notSpending = rows.filter { $0.notSpending && $0.flag == nil }.count
        return Section(footer: Text("Ticked rows are logged. Money received goes to Needs Review so you can match paybacks. Tap Split to share a spend, just like a new expense.")) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(rows.count) transactions found").font(.headline)
                if duplicates > 0 {
                    Text("\(duplicates) already logged — unticked").font(.subheadline).foregroundColor(.orange)
                }
                if billPayments > 0 {
                    Text("\(billPayments) card bill payment\(billPayments == 1 ? "" : "s") — unticked, not spending").font(.subheadline).foregroundColor(.secondary)
                }
                if ownTransfers > 0 {
                    Text("\(ownTransfers) transfer\(ownTransfers == 1 ? "" : "s") between your own accounts — unticked").font(.subheadline).foregroundColor(.purple)
                }
                if notSpending > 0 {
                    Text("\(notSpending) not your spending — logged to the UPI & Cash / Card tab only").font(.subheadline).foregroundColor(.secondary)
                }
                if splitCount > 0 {
                    Text("\(splitCount) already imported as split").font(.subheadline).foregroundColor(.green)
                }
            }
            HStack {
                Text(source == .card ? "Card" : "Account")
                Spacer()
                TextField("Last 4 digits", text: $account)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            Button("Choose a different file") {
                rows = []
                fileURL = nil
            }
        }
    }

    private func rowView(_ row: Binding<StatementRow>) -> some View {
        let r = row.wrappedValue
        return HStack(spacing: 12) {
            Button { row.include.wrappedValue.toggle() } label: {
                Image(systemName: r.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(r.include ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 3) {
                // Tap the name to rename / recategorise this payee (remembered for next time).
                Button { renaming = r } label: {
                    HStack(spacing: 4) {
                        Text(r.merchant).font(.headline).lineLimit(1)
                        Image(systemName: "pencil").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.borderless)
                .foregroundColor(.primary)
                if !r.isCredit {
                    HStack(spacing: 3) {
                        Image(systemName: r.category.icon)
                        Text(r.category.rawValue)
                    }
                    .font(.caption2).foregroundColor(r.category.colorValue)
                }
                Text(r.date, style: .date).font(.caption).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    if r.flag == .duplicate { badge("Already logged", .orange) }
                    if r.flag == .cardBillPayment { badge("Card bill payment", .gray) }
                    if r.flag == .selfTransfer { badge("Own account", .purple) }
                    if r.notSpending && !r.isCredit && r.flag == nil { badge("Not spending", .gray) }
                    if r.isCredit && r.flag != .selfTransfer { badge("Money received", .green) }
                    if !r.isCredit && r.flag == nil {
                        Button("Split") { split(r.id) }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text((r.isCredit ? "+" : "") + NotificationManager.currency(r.amount))
                    .font(.headline)
                    .foregroundColor(r.isCredit ? .green : .primary)
                Menu {
                    Picker("Paid via", selection: row.method) {
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Label(method.rawValue, systemImage: method.icon).tag(method)
                        }
                    }
                } label: {
                    Label(r.method.rawValue, systemImage: r.method.icon).font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(r.include ? 1 : 0.55)
    }

    private func samePayee(_ a: StatementRow, _ b: StatementRow) -> Bool {
        MerchantNamer.key(a.sourceKey) == MerchantNamer.key(b.sourceKey)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundColor(color)
    }

    // MARK: - Import

    /// Log this spend now and open the normal split editor on it.
    private func split(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }),
              let expense = expenseManager.importStatementRows(withAccount([rows[index]])).first else { return }
        rows.remove(at: index)
        splitCount += 1
        splitting = expense
    }

    private func importSelected() {
        let chosen = selected
        expenseManager.importStatementRows(withAccount(chosen))
        lastImport = (chosen.count + splitCount, chosen.filter(\.isCredit).count)
        showingDone = true
    }

    private var doneMessage: String {
        var text = "Logged \(lastImport.logged) transaction\(lastImport.logged == 1 ? "" : "s")."
        if lastImport.credits > 0 {
            text += " \(lastImport.credits) payment\(lastImport.credits == 1 ? "" : "s") received \(lastImport.credits == 1 ? "is" : "are") waiting in Needs Review to match."
        }
        return text
    }
}

/// Rename / recategorise one payee in the import preview; applies to all its
/// rows and is remembered for future imports.
struct PayeeEditView: View {
    @Environment(\.dismiss) var dismiss
    let row: StatementRow
    let sameCount: Int
    /// Name, category, and the own-account / not-spending switches — nil if you didn't touch them.
    let onSave: (String, ExpenseCategory, Bool?, Bool?) -> Void

    @State private var name: String
    @State private var category: ExpenseCategory
    @State private var ownAccount: Bool
    @State private var notSpending: Bool

    init(row: StatementRow, sameCount: Int, onSave: @escaping (String, ExpenseCategory, Bool?, Bool?) -> Void) {
        self.row = row
        self.sameCount = sameCount
        self.onSave = onSave
        _name = State(initialValue: row.merchant)
        _category = State(initialValue: row.category)
        _ownAccount = State(initialValue: row.flag == .selfTransfer)
        _notSpending = State(initialValue: row.notSpending)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Name"), footer: Text("The bank wrote: \(row.sourceKey)")) {
                    TextField("Who is this?", text: $name)
                        .autocorrectionDisabled()   // payee names: "Kirana" shouldn't become "Koran's"
                }
                Section(footer: Text(sameCount > 1
                                     ? "Applies to all \(sameCount) transactions from this payee here, and to future imports."
                                     : "Future imports from this payee will use this too.")) {
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { c in
                            Label(c.rawValue, systemImage: c.icon).tag(c)
                        }
                    }
                }
                Section(footer: Text("Transfers to your own accounts aren't spending or paybacks, so they're left unticked.")) {
                    Toggle("This is my own account", isOn: $ownAccount)
                }
                if !row.isCredit {
                    Section(footer: Text("For money you send that isn't your own spending, like to family. It's logged to the UPI & Cash / Card tab but stays out of Expenses and Summary.")) {
                        Toggle("Not my spending", isOn: $notSpending)
                    }
                }
            }
            .navigationTitle("Payee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let ownChanged = ownAccount != (row.flag == .selfTransfer)
                        let notSpendingChanged = notSpending != row.notSpending
                        onSave(name.trimmingCharacters(in: .whitespaces), category, ownChanged ? ownAccount : nil,
                               notSpendingChanged ? notSpending : nil)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    StatementImportView().environmentObject(ExpenseManager())
}
