//
//  ContactPicker.swift
//  Expense Tracker
//
//  Wraps the system contact picker. CNContactPickerViewController runs
//  out-of-process, so it needs no Contacts permission prompt or entitlement —
//  the app only receives the contact the user explicitly taps.
//

import SwiftUI
import ContactsUI

struct PickedContact {
    var name: String
    var identifier: String
}

struct ContactPicker: UIViewControllerRepresentable {
    var onPick: (PickedContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (PickedContact) -> Void

        init(onPick: @escaping (PickedContact) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let display = name.isEmpty ? "Unnamed" : name
            onPick(PickedContact(name: display, identifier: contact.identifier))
        }
    }
}
