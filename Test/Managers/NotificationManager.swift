//
//  NotificationManager.swift
//  Expense Tracker
//
//  Local-notification nudges for auto-captured transactions.
//

import Foundation
import Combine
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    /// Flipped true when the user taps a transaction nudge; the UI shows the review inbox.
    @Published var showReviewInbox = false

    private override init() { super.init() }

    /// Set the delegate so notification taps route to the review inbox (call at launch).
    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask for notification permission at a natural moment (e.g. auto-capture setup).
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Fire an immediate nudge right after a transaction is auto-logged.
    func notifyLogged(title: String, amount: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Transaction logged"
        content.body = "\(Self.currency(amount)) at \(title) — tap to add a note or category."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Nudge after money comes in, asking the user to match it to a share.
    func notifyReceived(sender: String, amount: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Money received"
        content.body = "\(Self.currency(amount)) from \(sender) — tap to match it to who owes you."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated static func currency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale.current
        return f.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { NotificationManager.shared.showReviewInbox = true }
    }
}
