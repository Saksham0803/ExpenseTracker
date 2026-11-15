//
//  MessageImportView.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import SwiftUI

struct MessageImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager
    
    @State private var messageText: String
    @State private var parsedTransactions: [ParsedTransaction] = []
    @State private var isProcessing = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingStatementImport = false

    private let parser = TransactionParser()
    
    init(initialMessage: String = "") {
        _messageText = State(initialValue: initialMessage)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Past history in bulk
                    Button {
                        showingStatementImport = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import a bank or card statement")
                                    .font(.headline)
                                Text("Log months of past transactions at once")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    // Instructions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Import Transaction Messages")
                            .font(.headline)
                        
                        Text("Paste transaction messages from your bank, payment apps, or SMS. The app will automatically extract transaction details.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    
                    // Text Input Area
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message Text")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $messageText)
                            .frame(height: 200)
                            .padding(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .onChange(of: messageText) { _ in
                                parseMessages()
                            }
                    }
                    
                    // Parse Button
                    Button {
                        parseMessages()
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "magnifyingglass")
                                Text("Parse Messages")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(messageText.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(messageText.isEmpty || isProcessing)
                    
                    // Parsed Transactions
                    if !parsedTransactions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Found \(parsedTransactions.count) transaction(s)")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                ForEach(Array(parsedTransactions.enumerated()), id: \.offset) { index, transaction in
                                    ParsedTransactionCard(transaction: transaction)
                                        .onTapGesture {
                                            showTransactionDetails(transaction)
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Add All Button
                    if !parsedTransactions.isEmpty {
                        Button {
                            addAllTransactions()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add All Transactions")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("Import Messages")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingStatementImport) {
                StatementImportView().environmentObject(expenseManager)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Successfully added \(parsedTransactions.count) transaction(s)")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                if !messageText.isEmpty {
                    parseMessages()
                }
            }
        }
    }
    
    private func parseMessages() {
        guard !messageText.isEmpty else {
            parsedTransactions = []
            return
        }
        
        isProcessing = true
        
        // Split by newlines and parse each line
        let lines = messageText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Try parsing each line individually
        var transactions: [ParsedTransaction] = []
        for line in lines {
            if let transaction = parser.parseMessage(line) {
                transactions.append(transaction)
            }
        }
        
        // If no individual lines worked, try parsing the whole text
        if transactions.isEmpty {
            if let transaction = parser.parseMessage(messageText) {
                transactions.append(transaction)
            }
        }
        
        parsedTransactions = transactions
        isProcessing = false
    }
    
    private func showTransactionDetails(_ transaction: ParsedTransaction) {
        // Convert date to IST timezone
        let istTimeZone = TimeZone(identifier: "Asia/Kolkata")!
        let transactionDate = transaction.date ?? Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: istTimeZone, from: transactionDate)
        let istDate = calendar.date(from: components) ?? transactionDate

        record(transaction, date: istDate)
        showSuccessAlert = true
    }

    private func addAllTransactions() {
        let istTimeZone = TimeZone(identifier: "Asia/Kolkata")!
        let calendar = Calendar.current

        for transaction in parsedTransactions {
            // Convert date to IST timezone
            let transactionDate = transaction.date ?? Date()
            let components = calendar.dateComponents(in: istTimeZone, from: transactionDate)
            let istDate = calendar.date(from: components) ?? transactionDate

            record(transaction, date: istDate)
        }

        showSuccessAlert = true
    }

    /// Debits become expenses flagged for a quick note; credits wait in the
    /// review inbox to be matched against who owes you (never counted as spending).
    private func record(_ transaction: ParsedTransaction, date: Date) {
        let named = MerchantNamer.resolve(transaction.merchant)
        if transaction.isCredit {
            expenseManager.addReceivedPayment(ReceivedPayment(
                amount: transaction.amount,
                sender: named.name,
                date: date,
                rawMessage: transaction.rawMessage,
                method: transaction.method,
                account: transaction.account
            ))
            return
        }
        expenseManager.addExpense(Expense(
            title: named.name,
            amount: transaction.amount,
            category: named.category ?? transaction.category ?? .other,
            type: .expense,
            date: date,
            notes: "",
            paymentMethod: transaction.method,
            needsReview: true,
            sourceKey: transaction.merchant,
            account: transaction.account,
            transfer: MerchantNamer.notSpending(transaction.merchant) == true ? true : nil
        ))
    }
}

struct ParsedTransactionCard: View {
    let transaction: ParsedTransaction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.merchant)
                        .font(.headline)

                    if transaction.isCredit {
                        Label("Money received", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if let category = transaction.category {
                        HStack {
                            Image(systemName: category.icon)
                                .font(.caption)
                            Text(category.rawValue)
                                .font(.caption)
                        }
                        .foregroundColor(category.colorValue)
                    }
                }
                
                Spacer()
                
                Text((transaction.isCredit ? "+" : "") + formatCurrency(transaction.amount))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(transaction.isCredit ? .green : .primary)
            }
            
            if let date = transaction.date {
                Text("Date: \(formatDate(date))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(transaction.rawMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
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
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    MessageImportView()
        .environmentObject(ExpenseManager())
}
