//
//  TransactionParser.swift
//  Expense Tracker
//
//  Created on Jan 31, 2026
//

import Foundation

struct ParsedTransaction {
    let amount: Double
    let merchant: String
    let date: Date?
    let category: ExpenseCategory?
    /// Payment method mentioned in the message (UPI / card), if any.
    let method: PaymentMethod?
    /// True when money came in (credited / received / refund) rather than went out.
    let isCredit: Bool
    /// Last 4 digits of your account / card ("A/C XXXXXX1234" → "1234"), if mentioned.
    let account: String?
    let rawMessage: String
}

class TransactionParser {

    func parseMessage(_ message: String) -> ParsedTransaction? {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = extractAmount(from: cleaned) ?? extractBareAmount(from: cleaned) else { return nil }

        let credit = isCredit(cleaned)
        // For money received, the useful name is who sent it, not a merchant. Some
        // banks don't say (BOB: "Your account is credited with INR 2385.00 … by UPI").
        let method = inferMethod(from: cleaned)
        let unnamed = credit ? (method == .upi ? "UPI credit" : "Bank credit") : "Transaction"
        let merchant = (credit ? extractSender(from: cleaned) : extractMerchant(from: cleaned)) ?? unnamed
        let date = extractDate(from: cleaned)
        let category = inferCategory(from: merchant)

        return ParsedTransaction(
            amount: amount,
            merchant: merchant,
            date: date,
            category: category,
            method: method,
            isCredit: credit,
            account: extractAccount(from: cleaned),
            rawMessage: cleaned
        )
    }

    /// Your account / card is the first one named: "Dr. from A/C XXXXXX1234 and Cr. to …",
    /// "From HDFC Bank A/C *5678", "A/c XX5678", "Card ending 1234". Keeps the last 4 digits.
    private func extractAccount(from message: String) -> String? {
        let pattern = #"(?i)\b(?:a/c|acct|account|card)(?:\s+(?:no\.?|number|ending(?:\s+with)?))?\s*[:.]?\s*[X*•.]*\s?(\d{3,18})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else { return nil }
        return String(message[range].suffix(4))
    }

    private static let debitWords = [#"\bdebited\b"#, #"\bdr\b"#, #"\bspent\b"#, #"\bsent\b"#, #"\bpaid\b"#,
                                     #"\bwithdrawn\b"#, #"\bdebit\b"#, #"\bpurchase"#]
    private static let creditWords = [#"\bcredited\b"#, #"\bcr\b"#, #"\breceived\b"#, #"\brefund"#, #"\bdeposited\b"#]

    /// Money in or out, from whichever money word comes first — the opening clause
    /// is about your account: "Rs.1.00 Dr. from A/C …1234 and Cr. to friend@oksbi"
    /// is a debit, "Acct XX12 credited with Rs 500 … paid by RAHUL" a credit.
    private func isCredit(_ message: String) -> Bool {
        let debit = Self.firstMatch(of: Self.debitWords, in: message)
        let credit = Self.firstMatch(of: Self.creditWords, in: message)
        switch (debit, credit) {
        case let (d?, c?): return c < d
        case (nil, _?): return true
        default: return false
        }
    }

    private static func firstMatch(of patterns: [String], in message: String) -> String.Index? {
        patterns.compactMap { message.range(of: $0, options: [.regularExpression, .caseInsensitive])?.lowerBound }.min()
    }

    /// A real bank/card/UPI alert, not an offer or a chat: it says money moved
    /// and names an account, card, UPI or a UPI handle. Auto-capture ignores the rest.
    static func looksLikeBankTransaction(_ message: String) -> Bool {
        guard firstMatch(of: debitWords + creditWords, in: message) != nil else { return false }
        let reference = #"\b(a/c|acct|account|card|upi|vpa)\b|[A-Za-z0-9._-]+@[A-Za-z]+"#
        return message.range(of: reference, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Name part of a UPI handle ("friend123@oksbi" → "friend123").
    private func handleName(in message: String) -> String? {
        guard let range = message.range(of: #"[A-Za-z0-9][A-Za-z0-9._-]*(?=@[A-Za-z]+)"#, options: .regularExpression) else { return nil }
        return String(message[range]).replacingOccurrences(of: #"-\d{1,2}$"#, with: "", options: .regularExpression)
    }

    /// Who the money came from: "from <name>", else the name part of a UPI VPA.
    private func extractSender(from message: String) -> String? {
        let stop = #"(?=\s+(?:on|via|ref|dated|txn|info|avl|bal|upi|a/c|ac|vpa|to|into)\b|[.,;:!(]|$)"#
        if let regex = try? NSRegularExpression(pattern: "(?i)\\bfrom\\s+([A-Za-z][A-Za-z0-9&'.\\- ]*?)\(stop)"),
           let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
           let range = Range(match.range(at: 1), in: message) {
            let candidate = cleanMerchantName(String(message[range]))
            let lower = candidate.lowercased()
            if !candidate.isEmpty && !lower.hasPrefix("a/c") && !lower.hasPrefix("ac ") && !lower.hasPrefix("your") {
                return candidate
            }
        }
        return handleName(in: message)
    }

    /// UPI if the message mentions UPI/VPA, card if it mentions a card, UPI if it
    /// names a UPI handle ("to friend@oksbi"); otherwise unknown.
    private func inferMethod(from message: String) -> PaymentMethod? {
        let lower = message.lowercased()
        if lower.contains("upi") || lower.contains("vpa") { return .upi }
        if lower.contains("card") { return .card }
        if handleName(in: message) != nil { return .upi }
        return nil
    }

    /// First currency-prefixed amount in the message (handles amount before or
    /// after the debit keyword, commas, and ₹/Rs/INR symbols).
    private func extractAmount(from message: String) -> Double? {
        let pattern = #"(?:Rs\.?|INR|₹|USD|\$|€|£)\s*([\d,]+(?:\.\d{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else {
            return nil
        }
        let cleaned = String(message[range]).replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    /// Some banks print no currency: "A/C X1234 debited by 20.0 on …" (SBI UPI).
    private func extractBareAmount(from message: String) -> Double? {
        let pattern = #"(?i)\b(?:debited|credited)\s+(?:by|for|with)\s+([\d,]+(?:\.\d{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else { return nil }
        return Double(message[range].replacingOccurrences(of: ",", with: ""))
    }

    /// Merchant/payee after "at"/"to"/"@"/"for", stopping at trailing noise
    /// (on <date>, via UPI, Ref…, etc.).
    private func extractMerchant(from message: String) -> String? {
        let stop = #"(?=\s*\n|\s+(?:on|via|ref|refno|dated|txn|info|avl|bal|using|through|upi|a/c|ac)\b|[.,;!]|$)"#
        // ICICI style: "Acct XX123 debited for Rs 349.00 on …; ZOMATO credited."
        if let range = message.range(of: #"(?i);\s*[A-Za-z][A-Za-z0-9&'.\- ]*?(?=\s+credited\b)"#, options: .regularExpression) {
            let candidate = cleanMerchantName(String(message[range].dropFirst()))
            if !candidate.isEmpty { return candidate }
        }
        for keyword in ["at", "to", "@", "for"] {
            let pattern = "(?i)\\b\(keyword)\\s+([A-Za-z0-9&'.\\- ]+?)\(stop)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
                  let range = Range(match.range(at: 1), in: message) else {
                continue
            }
            let candidate = cleanMerchantName(String(message[range]))
            let lower = candidate.lowercased()
            // Skip account-number targets like "A/c XX1234" and amounts like "for Rs 349".
            if candidate.isEmpty || lower.hasPrefix("a/c") || lower.hasPrefix("ac ")
                || lower.hasPrefix("rs") || lower.hasPrefix("inr") || candidate.first?.isNumber == true { continue }
            return candidate
        }
        // Payee given only as a UPI handle: "Cr. to friend123@oksbi".
        return handleName(in: message)
    }
    
    private func cleanMerchantName(_ name: String) -> String {
        return name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
    
    private func extractDate(from message: String) -> Date? {
        let dateFormats = [
            "dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd",
            "dd-MM-yyyy", "dd MMM yyyy", "MMM dd, yyyy",
            "dd/MM/yy", "MM/dd/yy"
        ]
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        for format in dateFormats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: message) {
                return date
            }
        }
        
        // Try relative dates
        let relativePatterns = [
            ("today", 0),
            ("yesterday", -1),
            ("tomorrow", 1)
        ]
        
        for (keyword, daysOffset) in relativePatterns {
            if message.localizedCaseInsensitiveContains(keyword) {
                return Calendar.current.date(byAdding: .day, value: daysOffset, to: Date())
            }
        }
        
        return nil
    }
    
    func inferCategory(from merchant: String) -> ExpenseCategory {
        let lowerMerchant = merchant.lowercased()

        // Quick commerce
        if lowerMerchant.contains("blinkit") || lowerMerchant.contains("zepto") ||
           lowerMerchant.contains("instamart") || lowerMerchant.contains("dunzo") {
            return .quickCommerce
        }

        // Food-related keywords
        if lowerMerchant.contains("restaurant") || lowerMerchant.contains("cafe") ||
           lowerMerchant.contains("food") || lowerMerchant.contains("pizza") ||
           lowerMerchant.contains("burger") || lowerMerchant.contains("starbucks") ||
           lowerMerchant.contains("mcdonald") || lowerMerchant.contains("swiggy") ||
           lowerMerchant.contains("zomato") || lowerMerchant.contains("uber eats") {
            return .food
        }
        
        // Transportation
        if lowerMerchant.contains("uber") || lowerMerchant.contains("lyft") ||
           lowerMerchant.contains("taxi") || lowerMerchant.contains("cab") ||
           lowerMerchant.contains("gas") || lowerMerchant.contains("petrol") ||
           lowerMerchant.contains("fuel") || lowerMerchant.contains("metro") ||
           lowerMerchant.contains("bus") || lowerMerchant.contains("train") {
            return .transportation
        }
        
        // Shopping
        if lowerMerchant.contains("amazon") || lowerMerchant.contains("flipkart") ||
           lowerMerchant.contains("walmart") || lowerMerchant.contains("target") ||
           lowerMerchant.contains("mall") || lowerMerchant.contains("store") {
            return .shopping
        }
        
        // Bills
        if lowerMerchant.contains("electric") || lowerMerchant.contains("water") ||
           lowerMerchant.contains("phone") || lowerMerchant.contains("internet") ||
           lowerMerchant.contains("utility") || lowerMerchant.contains("bill") {
            return .bills
        }
        
        // Healthcare
        if lowerMerchant.contains("pharmacy") || lowerMerchant.contains("hospital") ||
           lowerMerchant.contains("clinic") || lowerMerchant.contains("medical") ||
           lowerMerchant.contains("doctor") || lowerMerchant.contains("apollo") {
            return .healthcare
        }
        
        // Entertainment
        if lowerMerchant.contains("netflix") || lowerMerchant.contains("spotify") ||
           lowerMerchant.contains("movie") || lowerMerchant.contains("cinema") ||
           lowerMerchant.contains("theater") || lowerMerchant.contains("game") {
            return .entertainment
        }
        
        return .other
    }
    
    func parseMultipleMessages(_ messages: [String]) -> [ParsedTransaction] {
        return messages.compactMap { parseMessage($0) }
    }
}
