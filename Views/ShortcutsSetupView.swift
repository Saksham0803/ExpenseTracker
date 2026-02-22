//
//  ShortcutsSetupView.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import SwiftUI

struct ShortcutsSetupView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "app.badge")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("iOS Shortcuts Integration")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Add expenses quickly using Siri or Shortcuts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top)
                    
                    // Benefits
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Why Use Shortcuts?")
                            .font(.headline)
                        
                        FeatureRow(
                            icon: "mic.fill",
                            title: "Voice Control",
                            description: "Say 'Hey Siri, add expense' to log expenses hands-free"
                        )
                        
                        FeatureRow(
                            icon: "bolt.fill",
                            title: "Quick Entry",
                            description: "Add expenses in seconds without opening the app"
                        )
                        
                        FeatureRow(
                            icon: "checkmark.shield.fill",
                            title: "Apple Approved",
                            description: "100% legal and privacy-friendly - no scraping needed"
                        )
                        
                        FeatureRow(
                            icon: "link",
                            title: "Automation",
                            description: "Create shortcuts that trigger after payments or at specific times"
                        )
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    
                    // Setup Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Setup Instructions")
                            .font(.headline)
                        
                        InstructionStep(
                            number: 1,
                            title: "Open Shortcuts App",
                            description: "Find and open the Shortcuts app on your iPhone"
                        )
                        
                        InstructionStep(
                            number: 2,
                            title: "Add New Shortcut",
                            description: "Tap the '+' button to create a new shortcut"
                        )
                        
                        InstructionStep(
                            number: 3,
                            title: "Search for 'Add Expense'",
                            description: "In the search bar, type 'Add Expense' and select the action from Expense Tracker"
                        )
                        
                        InstructionStep(
                            number: 4,
                            title: "Configure Parameters",
                            description: "Set up the shortcut to ask for amount, title, and category when run"
                        )
                        
                        InstructionStep(
                            number: 5,
                            title: "Add to Siri",
                            description: "Tap 'Add to Siri' and record a phrase like 'Log my expense'"
                        )
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    
                    // Quick Actions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quick Actions")
                            .font(.headline)
                        
                        Text("You can also use these Siri phrases:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            SiriPhrase(phrase: "Hey Siri, add expense")
                            SiriPhrase(phrase: "Hey Siri, log expense")
                            SiriPhrase(phrase: "Hey Siri, track expense")
                            SiriPhrase(phrase: "Hey Siri, record expense")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    
                    // URL Scheme Alternative
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Advanced: URL Scheme")
                            .font(.headline)
                        
                        Text("For advanced users, you can also use URL schemes to add expenses programmatically:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        CodeBlock(text: "expensetracker://add?title=Coffee&amount=5.50&category=Food")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    
                    // Open Shortcuts Button
                    Button {
                        openShortcutsApp()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Open Shortcuts App")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Shortcuts Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SiriPhrase: View {
    let phrase: String
    
    var body: some View {
        HStack {
            Image(systemName: "mic.fill")
                .foregroundColor(.blue)
                .font(.caption)
            
            Text(phrase)
                .font(.caption)
                .fontFamily(.monospaced)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
        )
    }
}

struct CodeBlock: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
    }
}

extension View {
    func fontFamily(_ style: Font.TextStyle) -> some View {
        self.font(.system(style, design: .monospaced))
    }
}

#Preview {
    ShortcutsSetupView()
}
