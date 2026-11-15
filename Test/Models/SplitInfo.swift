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
    /// Fully paid back (set by the one-tap settle, or once paybacks cover `amount`).
    var isSettled: Bool
    /// Partial paybacks received so far. Optional for backward compatibility.
    var paidBack: Double?

    nonisolated init(id: UUID = UUID(), name: String, contactIdentifier: String? = nil, amount: Double, isSettled: Bool = false, paidBack: Double? = nil) {
        self.id = id
        self.name = name
        self.contactIdentifier = contactIdentifier
        self.amount = amount
        self.isSettled = isSettled
        self.paidBack = paidBack
    }

    /// How much of their share they've paid back.
    var received: Double { isSettled ? amount : min(paidBack ?? 0, amount) }

    /// How much they still owe.
    var remaining: Double { max(0, amount - received) }
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

    /// Amount participants have already paid back (including partial paybacks).
    var settledTotal: Double {
        participants.reduce(0) { $0 + $1.received }
    }

    /// Amount still owed to you.
    var outstandingTotal: Double {
        participants.reduce(0) { $0 + $1.remaining }
    }

    /// Your own share of the charge — what counts as your spending.
    var myShare: Double {
        max(0, totalAmount - participantsTotal)
    }
}

/// Money that came in (a "credited" SMS) and hasn't been matched yet. It never
/// counts as spending; once you match it to someone's share, mark it a refund, or
/// dismiss it, it's removed.
struct ReceivedPayment: Identifiable, Codable {
    let id: UUID
    /// Amount still unallocated (drops as you apply it to shares).
    var amount: Double
    var sender: String
    var date: Date
    var rawMessage: String
    /// Where the money landed, when known (statement imports); used if it's marked a refund.
    var method: PaymentMethod?
    /// Last 4 digits of the account / card it landed in, when known.
    var account: String?

    nonisolated init(id: UUID = UUID(), amount: Double, sender: String, date: Date = Date(), rawMessage: String = "", method: PaymentMethod? = nil, account: String? = nil) {
        self.id = id
        self.amount = amount
        self.sender = sender
        self.date = date
        self.rawMessage = rawMessage
        self.method = method
        self.account = account
    }
}

/// An open share someone owes you, offered as a match for a received payment.
struct ShareMatch: Identifiable {
    var id: UUID { participantID }
    let expenseID: UUID
    let participantID: UUID
    let personName: String
    let expenseTitle: String
    let remaining: Double
    let nameMatches: Bool
    let amountMatches: Bool
}
