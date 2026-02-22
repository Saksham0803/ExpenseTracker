//
//  BackupView.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct BackupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var expenseManager: ExpenseManager
    
    @State private var showingExportSuccess = false
    @State private var showingImportSuccess = false
    @State private var showingImportError = false
    @State private var importErrorMessage = ""
    @State private var showingReplaceConfirmation = false
    @State private var importData: Data?
    @State private var showingImportPicker = false
    @State private var pendingReplace = false
    @State private var showingExportPicker = false
    @State private var exportFile: ExportFile?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Export Backup")) {
                    Text("Export all your expense data to a JSON file that you can save on your Mac or iCloud Drive.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: { prepareExport() }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                            Text("Export to File")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    if showingExportSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Export successful! Check Files app or Downloads")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Section(header: Text("Import Backup")) {
                    Text("Import expenses from a previously exported backup file. You can merge (add new expenses) or replace (overwrite all data).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: { pendingReplace = false; showingImportPicker = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.blue)
                            Text("Import & Merge (Add New Expenses)")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Button(action: { pendingReplace = true; showingImportPicker = true }) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundColor(.orange)
                            Text("Import & Replace (Overwrite All Data)")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if showingImportSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Import successful!")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    if showingImportError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(importErrorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section(header: Text("Backup Information")) {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(icon: "info.circle", text: "Total Expenses: \(expenseManager.expenses.count)")
                        InfoRow(icon: "calendar", text: "Last Backup: Create one now!")
                        InfoRow(icon: "lock.shield", text: "Data is stored locally and encrypted by iOS")
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Tips")) {
                    VStack(alignment: .leading, spacing: 8) {
                        TipRow(text: "Export regularly (weekly/monthly) for safety")
                        TipRow(text: "Save backups to iCloud Drive for cloud access")
                        TipRow(text: "Keep multiple backup files with different dates")
                        TipRow(text: "Backups are JSON files - readable on any device")
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Backup & Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileExporter(
                isPresented: $showingExportPicker,
                document: exportFile,
                contentType: .json,
                defaultFilename: expenseManager.getExportFileName()
            ) { result in
                handleExportResult(result)
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result, replace: pendingReplace)
            }
            .alert("Replace All Data?", isPresented: $showingReplaceConfirmation) {
                Button("Cancel", role: .cancel) {
                    importData = nil
                }
                Button("Replace", role: .destructive) {
                    if let data = importData {
                        if expenseManager.replaceExpenses(with: data) {
                            showingImportSuccess = true
                            showingImportError = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showingImportSuccess = false
                            }
                        } else {
                            showingImportError = true
                            importErrorMessage = "Failed to import. Invalid file format."
                        }
                        importData = nil
                    }
                }
            } message: {
                Text("This will replace all \(expenseManager.expenses.count) existing expenses with the imported data. This action cannot be undone.")
            }
        }
    }
    
    private func prepareExport() {
        guard let data = expenseManager.exportExpenses() else {
            showingImportError = true
            importErrorMessage = "Failed to export data."
            return
        }
        
        exportFile = ExportFile(data: data, fileName: expenseManager.getExportFileName())
        showingExportPicker = true
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            showingExportSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showingExportSuccess = false
            }
        case .failure(let error):
            showingImportError = true
            importErrorMessage = "Export failed: \(error.localizedDescription)"
        }
        exportFile = nil
    }
    
    private func handleImport(result: Result<[URL], Error>, replace: Bool) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                showingImportError = true
                importErrorMessage = "Cannot access file. Please try again."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                
                if replace {
                    // Show confirmation dialog
                    importData = data
                    showingReplaceConfirmation = true
                } else {
                    // Merge data
                    if expenseManager.importExpenses(from: data) {
                        showingImportSuccess = true
                        showingImportError = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showingImportSuccess = false
                        }
                    } else {
                        showingImportError = true
                        importErrorMessage = "No new expenses to import, or invalid file format."
                    }
                }
            } catch {
                showingImportError = true
                importErrorMessage = "Failed to read file: \(error.localizedDescription)"
            }
            
        case .failure(let error):
            showingImportError = true
            importErrorMessage = "Failed to import: \(error.localizedDescription)"
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.caption)
        }
    }
}

struct TipRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// Helper struct for file export
struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var data: Data
    var fileName: String
    
    init(data: Data, fileName: String) {
        self.data = data
        self.fileName = fileName
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        self.fileName = "backup.json"
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    BackupView()
        .environmentObject(ExpenseManager())
}
