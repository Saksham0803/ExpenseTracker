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
    
    private let parser = TransactionParser()
    
    init(initialMessage: String = "") {
        _messageText = State(initialValue: initialMessage)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
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
        var components = calendar.dateComponents(in: istTimeZone, from: transactionDate)
        let istDate = calendar.date(from: components) ?? transactionDate
        
        // Create expense from transaction
        let expense = Expense(
            title: transaction.merchant,
            amount: transaction.amount,
            category: transaction.category ?? .other,
            type: .expense,
            date: istDate,
            notes: transaction.rawMessage
        )
        
        // Show edit sheet
        // This would require passing a binding, so for now we'll just add it
        expenseManager.addExpense(expense)
        showSuccessAlert = true
    }
    
    private func addAllTransactions() {
        let istTimeZone = TimeZone(identifier: "Asia/Kolkata")!
        let calendar = Calendar.current
        
        for transaction in parsedTransactions {
            // Convert date to IST timezone
            let transactionDate = transaction.date ?? Date()
            var components = calendar.dateComponents(in: istTimeZone, from: transactionDate)
            let istDate = calendar.date(from: components) ?? transactionDate
            
            let expense = Expense(
                title: transaction.merchant,
                amount: transaction.amount,
                category: transaction.category ?? .other,
                date: istDate,
                notes: transaction.rawMessage
            )
            expenseManager.addExpense(expense)
        }
        
        showSuccessAlert = true
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
                    
                    if let category = transaction.category {
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
                
                Text(formatCurrency(transaction.amount))
                    .font(.title3)
                    .fontWeight(.bold)
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
