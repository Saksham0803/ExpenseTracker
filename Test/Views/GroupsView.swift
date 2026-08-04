//
//  GroupsView.swift
//  Expense Tracker
//
//  Manage reusable groups of people for credit-card splits.
//

import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    @Environment(\.dismiss) var dismiss

    @State private var editingGroup: PersonGroup?
    @State private var creatingNew = false

    var body: some View {
        NavigationView {
            Group {
                if expenseManager.groups.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(expenseManager.groups) { group in
                            Button {
                                editingGroup = group
                            } label: {
                                HStack {
                                    Image(systemName: "person.3.fill")
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.name)
                                            .foregroundColor(.primary)
                                        Text("\(group.members.count) \(group.members.count == 1 ? "person" : "people")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { expenseManager.deleteGroups(at: $0) }
                    }
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        creatingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingGroup) { group in
                GroupEditorView(group: group)
            }
            .sheet(isPresented: $creatingNew) {
                GroupEditorView(group: nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No groups yet")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Create a group like \"Flatmates\" to add everyone to a split in one tap.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                creatingNew = true
            } label: {
                Label("Create a group", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct GroupEditorView: View {
    @EnvironmentObject var expenseManager: ExpenseManager
    @Environment(\.dismiss) var dismiss

    let group: PersonGroup?

    @State private var name: String
    @State private var members: [GroupMember]
    @State private var showingContactPicker = false

    init(group: PersonGroup?) {
        self.group = group
        _name = State(initialValue: group?.name ?? "")
        _members = State(initialValue: group?.members ?? [])
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !members.isEmpty &&
        members.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Group name")) {
                    TextField("e.g. Flatmates", text: $name)
                }

                Section(header: Text("Members")) {
                    ForEach($members) { $member in
                        HStack {
                            Image(systemName: member.contactIdentifier != nil ? "person.crop.circle.fill" : "person.crop.circle")
                                .foregroundColor(.secondary)
                            TextField("Name", text: $member.name)
                        }
                    }
                    .onDelete { members.remove(atOffsets: $0) }

                    Button {
                        showingContactPicker = true
                    } label: {
                        Label("Add from contacts", systemImage: "person.crop.circle.badge.plus")
                    }

                    Button {
                        members.append(GroupMember(name: ""))
                    } label: {
                        Label("Add manually", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(group == nil ? "New Group" : "Edit Group")
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
                    members.append(GroupMember(name: picked.name, contactIdentifier: picked.identifier))
                }
            }
        }
    }

    private func save() {
        guard isValid else { return }
        let saved = PersonGroup(
            id: group?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            members: members
        )
        if group == nil {
            expenseManager.addGroup(saved)
        } else {
            expenseManager.updateGroup(saved)
        }
        dismiss()
    }
}

#Preview {
    GroupsView()
        .environmentObject(ExpenseManager())
}
