//
//  PersonGroup.swift
//  Expense Tracker
//
//  A reusable, saved group of people (e.g. "Flatmates") that can be dropped
//  into a credit-card split in one tap.
//

import Foundation

struct GroupMember: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// Contacts framework identifier, when picked from the address book.
    var contactIdentifier: String?

    nonisolated init(id: UUID = UUID(), name: String, contactIdentifier: String? = nil) {
        self.id = id
        self.name = name
        self.contactIdentifier = contactIdentifier
    }
}

struct PersonGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var members: [GroupMember]

    nonisolated init(id: UUID = UUID(), name: String, members: [GroupMember] = []) {
        self.id = id
        self.name = name
        self.members = members
    }
}
