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
    let rawMessage: String
}

class TransactionParser {
    
    // Common patterns for transaction messages
    private let patterns: [(pattern: String, amountIndex: Int, merchantIndex: Int?)] = [
        // Pattern: "You spent $50.00 at STORE NAME"
        (pattern: #"(?:spent|paid|debited|charged|transaction)\s+(?:of\s+)?(?:Rs\.?|INR|USD|\$|€|£)?\s*([\d,]+\.?\d*)\s*(?:at|from|to|with)\s+([A-Za-z0-9\s&'-]+?)(?:\s+on|\s+at|$|\.)"#, amountIndex: 1, merchantIndex: 2),
        
        // Pattern: "Payment of INR 500 to MERCHANT"
        (pattern: #"(?:payment|transaction|purchase|expense)\s+(?:of\s+)?(?:Rs\.?|INR|USD|\$|€|£)?\s*([\d,]+\.?\d*)\s+to\s+([A-Za-z0-9\s&'-]+?)(?:\s+on|\s+at|$|\.)"#, amountIndex: 1, merchantIndex: 2),
        
        // Pattern: "Debit: $25.99 at AMAZON"
        (pattern: #"(?:debit|credit|withdrawal|deposit):\s*(?:Rs\.?|INR|USD|\$|€|£)?\s*([\d,]+\.?\d*)\s+at\s+([A-Za-z0-9\s&'-]+?)(?:\s+on|\s+at|$|\.)"#, amountIndex: 1, merchantIndex: 2),
        
        // Pattern: "$50.00 charged at STORE"
        (pattern: #"(?:Rs\.?|INR|USD|\$|€|£)?\s*([\d,]+\.?\d*)\s+(?:charged|spent|paid|debited)\s+at\s+([A-Za-z0-9\s&'-]+?)(?:\s+on|\s+at|$|\.)"#, amountIndex: 1, merchantIndex: 2),
        
        // Pattern: "STORE NAME - $50.00"
        (pattern: #"([A-Za-z0-9\s&'-]+?)\s*[-–]\s*(?:Rs\.?|INR|USD|\$|€|£)?\s*([\d,]+\.?\d*)"#, amountIndex: 2, merchantIndex: 1),
        
        // Pattern: "Amount: $50.00 Merchant: STORE"
        (pattern: #"(?:amount|amt|value):\s*(?:Rs\.?|INR|USD|\$|€|£)?\s*([\d,]+\.?\d*).*?(?:merchant|vendor|store|to):\s*([A-Za-z0-9\s&'-]+)"#, amountIndex: 1, merchantIndex: 2),
        
        // Pattern: "INR 500.00 for MERCHANT"
        (pattern: #"(?:Rs\.?|INR|USD|\$|€|£)?\s*([\d,]+\.?\d*)\s+for\s+([A-Za-z0-9\s&'-]+?)(?:\s+on|\s+at|$|\.)"#, amountIndex: 1, merchantIndex: 2),
    ]
    
    func parseMessage(_ message: String) -> ParsedTransaction? {
        let cleanedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try each pattern
        for patternInfo in patterns {
            if let result = tryPattern(patternInfo.pattern, message: cleanedMessage, amountIndex: patternInfo.amountIndex, merchantIndex: patternInfo.merchantIndex) {
                return result
            }
        }
        
        // Fallback: Try to extract amount and merchant separately
        return tryFallbackParsing(cleanedMessage)
    }
    
    private func tryPattern(_ pattern: String, message: String, amountIndex: Int, merchantIndex: Int?) -> ParsedTransaction? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) else {
            return nil
        }
        
        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, options: [], range: range) else {
            return nil
        }
        
        // Extract amount
        guard let amountRange = Range(match.range(at: amountIndex), in: message),
              let amount = extractAmount(from: String(message[amountRange])) else {
            return nil
        }
        
        // Extract merchant
        var merchant = "Unknown"
        if let merchantIdx = merchantIndex, merchantIdx < match.numberOfRanges {
            if let merchantRange = Range(match.range(at: merchantIdx), in: message) {
                merchant = String(message[merchantRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                merchant = cleanMerchantName(merchant)
            }
        }
        
        // Try to extract date
        let date = extractDate(from: message)
        
        // Try to infer category from merchant name
        let category = inferCategory(from: merchant)
        
        return ParsedTransaction(
            amount: amount,
            merchant: merchant,
            date: date,
            category: category,
            rawMessage: message
        )
    }
    
    private func tryFallbackParsing(_ message: String) -> ParsedTransaction? {
        // Look for amount patterns
        let amountPattern = #"(?:Rs\.?|INR|USD|\$|€|£)?\s*([\d,]+\.?\d*)"#
        guard let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: .caseInsensitive),
              let amountMatch = amountRegex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let amountRange = Range(amountMatch.range(at: 1), in: message),
              let amount = extractAmount(from: String(message[amountRange])) else {
            return nil
        }
        
        // Try to find merchant name (look for common words before/after amount)
        var merchant = "Transaction"
        let merchantPatterns = [
            #"at\s+([A-Za-z0-9\s&'-]+?)(?:\s+on|\s+at|$|\.)"#,
            #"to\s+([A-Za-z0-9\s&'-]+?)(?:\s+on|\s+at|$|\.)"#,
            #"from\s+([A-Za-z0-9\s&'-]+?)(?:\s+on|\s+at|$|\.)"#
        ]
        
        for pattern in merchantPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
               let merchantRange = Range(match.range(at: 1), in: message) {
                merchant = String(message[merchantRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                merchant = cleanMerchantName(merchant)
                break
            }
        }
        
        let date = extractDate(from: message)
        let category = inferCategory(from: merchant)
        
        return ParsedTransaction(
            amount: amount,
            merchant: merchant,
            date: date,
            category: category,
            rawMessage: message
        )
    }
    
    private func extractAmount(from string: String) -> Double? {
        // Remove currency symbols and commas
        let cleaned = string.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "Rs.", with: "")
            .replacingOccurrences(of: "Rs", with: "")
            .replacingOccurrences(of: "INR", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        return Double(cleaned)
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
    
    private func inferCategory(from merchant: String) -> ExpenseCategory {
        let lowerMerchant = merchant.lowercased()
        
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
