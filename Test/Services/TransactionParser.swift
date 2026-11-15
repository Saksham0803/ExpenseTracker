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
    let rawMessage: String
}

class TransactionParser {

    func parseMessage(_ message: String) -> ParsedTransaction? {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = extractAmount(from: cleaned) else { return nil }

        let credit = isCredit(cleaned)
        // For money received, the useful name is who sent it, not a merchant.
        let merchant = (credit ? extractSender(from: cleaned) : extractMerchant(from: cleaned)) ?? "Transaction"
        let date = extractDate(from: cleaned)
        let category = inferCategory(from: merchant)

        return ParsedTransaction(
            amount: amount,
            merchant: merchant,
            date: date,
            category: category,
            method: inferMethod(from: cleaned),
            isCredit: credit,
            rawMessage: cleaned
        )
    }

    /// Money in: mentions credited/received/refund and none of the debit words.
    private func isCredit(_ message: String) -> Bool {
        let lower = message.lowercased()
        let creditWord = lower.contains("credited") || lower.contains("received") || lower.contains("refund")
        let debitWord = lower.contains("debited") || lower.contains("spent") || lower.contains("paid to") || lower.contains("sent to")
        return creditWord && !debitWord
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
        if let regex = try? NSRegularExpression(pattern: #"([A-Za-z][A-Za-z0-9._-]*)@[A-Za-z]+"#),
           let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
           let range = Range(match.range(at: 1), in: message) {
            return String(message[range])
        }
        return nil
    }

    /// UPI if the message mentions UPI/VPA, card if it mentions a card; otherwise unknown.
    private func inferMethod(from message: String) -> PaymentMethod? {
        let lower = message.lowercased()
        if lower.contains("upi") || lower.contains("vpa") { return .upi }
        if lower.contains("card") { return .card }
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

    /// Merchant/payee after "at"/"to"/"@"/"for", stopping at trailing noise
    /// (on <date>, via UPI, Ref…, etc.).
    private func extractMerchant(from message: String) -> String? {
        let stop = #"(?=\s+(?:on|via|ref|dated|txn|info|avl|bal|using|through|upi|a/c|ac)\b|[.,;!]|$)"#
        for keyword in ["at", "to", "@", "for"] {
            let pattern = "(?i)\\b\(keyword)\\s+([A-Za-z0-9&'.\\- ]+?)\(stop)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
                  let range = Range(match.range(at: 1), in: message) else {
                continue
            }
            let candidate = cleanMerchantName(String(message[range]))
            let lower = candidate.lowercased()
            // Skip account-number targets like "A/c XX1234".
            if candidate.isEmpty || lower.hasPrefix("a/c") || lower.hasPrefix("ac ") { continue }
            return candidate
        }
        return nil
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
