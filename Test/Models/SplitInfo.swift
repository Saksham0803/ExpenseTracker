//
//  SplitInfo.swift
//  Expense Tracker
//
//  Split / credit-card recovery model.
//

import Foundation

/// A single person the payment was split with — someone who owes you back.
struct SplitParticipant: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// Contacts framework identifier, when picked from the address book.
    var contactIdentifier: String?
    /// How much this person owes you for this payment.
    var amount: Double
    var isSettled: Bool

    nonisolated init(id: UUID = UUID(), name: String, contactIdentifier: String? = nil, amount: Double, isSettled: Bool = false) {
        self.id = id
        self.name = name
        self.contactIdentifier = contactIdentifier
        self.amount = amount
        self.isSettled = isSettled
    }
}

/// Attached to an `Expense` when the charge was split with other people.
///
/// Invariant: `totalAmount` = your own share (`Expense.amount`) + the sum of every
/// participant's `amount`. Your own share is what flows into the regular spending
/// totals; the participants' portions are money owed back to you and are tracked
/// separately in the credit-card dashboard.
struct SplitInfo: Codable {
    /// The full amount that hit the card.
    var totalAmount: Double
    /// Whether your own contribution is part of this charge (drives spending totals).
    var myShareIncluded: Bool
    var participants: [SplitParticipant]

    nonisolated init(totalAmount: Double, myShareIncluded: Bool = true, participants: [SplitParticipant] = []) {
        self.totalAmount = totalAmount
        self.myShareIncluded = myShareIncluded
        self.participants = participants
    }

    /// Total owed to you by everyone (settled or not).
    var participantsTotal: Double {
        participants.reduce(0) { $0 + $1.amount }
    }

    /// Amount participants have already paid back.
    var settledTotal: Double {
        participants.filter { $0.isSettled }.reduce(0) { $0 + $1.amount }
    }

    /// Amount still owed to you.
    var outstandingTotal: Double {
        participants.filter { !$0.isSettled }.reduce(0) { $0 + $1.amount }
    }

    /// Your own share of the charge — what counts as your spending.
    var myShare: Double {
        max(0, totalAmount - participantsTotal)
    }
}
