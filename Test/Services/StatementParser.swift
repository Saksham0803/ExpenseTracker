//
//  StatementParser.swift
//  Expense Tracker
//
//  Turns a downloaded bank / credit-card statement (CSV or text PDF) into rows
//  the user reviews before logging. Layouts differ per bank, so this relies on
//  header names (CSV) and running balances (PDF) rather than one bank's format.
//

import Foundation
import PDFKit

enum StatementSource: String, CaseIterable, Identifiable {
    case bank = "Bank account"
    case card = "Credit card"
    var id: String { rawValue }
}

struct StatementRow: Identifiable {
    enum Flag { case duplicate, cardBillPayment, selfTransfer }

    let id = UUID()
    let date: Date
    let description: String
    var merchant: String
    /// The payee as the bank wrote it; renames/categories are remembered against it.
    let sourceKey: String
    let amount: Double
    let isCredit: Bool
    var category: ExpenseCategory
    var method: PaymentMethod
    var flag: Flag?
    var include = true

    /// Stable key so the same statement line is never imported twice.
    var fingerprint: String {
        let day = Int(date.timeIntervalSince1970 / 86_400)
        let text = description.lowercased().filter { !$0.isWhitespace }
        return "\(day)|\(String(format: "%.2f", amount))|\(isCredit ? "C" : "D")|\(text)"
    }
}

enum StatementError: LocalizedError {
    case unreadable, locked, wrongPassword, noTransactions

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Couldn't read this file. Use a CSV or PDF statement downloaded from your bank."
        case .locked: return "This PDF is password-protected."
        case .wrongPassword: return "That password didn't unlock the PDF."
        case .noTransactions: return "No transactions found. If this is a scanned PDF, download the CSV version instead."
        }
    }
}

final class StatementParser {
    private struct RawTxn {
        let date: Date
        let description: String
        let amount: Double
        var isCredit: Bool?
        var balance: Double?
        /// Wrapped narration lines (PDF), used only if the first line has no usable name.
        var extra = ""
        /// Layout clue to direction ("-" in the empty column), used if balances can't tell.
        var hint: Bool?
    }

    private let ist = TimeZone(identifier: "Asia/Kolkata")!
    /// Account holder's name words from the statement header, to spot transfers to your own accounts.
    private var holder: [String]?

    func parse(url: URL, source: StatementSource, password: String? = nil) throws -> [StatementRow] {
        let raw: [RawTxn]
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { throw StatementError.unreadable }
            if doc.isLocked {
                guard let password, !password.isEmpty else { throw StatementError.locked }
                guard doc.unlock(withPassword: password) else { throw StatementError.wrongPassword }
            }
            raw = parsePDF(doc, source: source)
        } else {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw StatementError.unreadable
            }
            raw = parseCSV(text, source: source)
        }
        guard !raw.isEmpty else { throw StatementError.noTransactions }
        return raw.map { makeRow($0, source: source) }
    }

    // MARK: - Row building

    private func makeRow(_ txn: RawTxn, source: StatementSource) -> StatementRow {
        let credit = txn.isCredit ?? txn.hint ?? guessCredit(txn.description)
        let upper = txn.description.uppercased()

        let method: PaymentMethod
        if source == .card {
            method = .card
        } else if ["ATM", "CASH WDL", "CASH WITHDRAWAL", "NWD", "ATW"].contains(where: upper.contains) {
            method = .cash
        } else {
            method = .upi
        }

        // Paying the card bill isn't spending — the card's own rows already are.
        let billPayment = source == .card
            ? credit && ["PAYMENT", "THANK YOU", "AUTOPAY", "BBPS"].contains(where: upper.contains)
            : !credit && ["CREDIT CARD", "CC PAY", "CARD BILL", "CRED CLUB", "CREDCLUB", "CRED.CLUB"].contains(where: upper.contains)


        // Card statements already print a merchant ("ZOMATOGURGAON"); bank narrations need digging.
        let raw: String
        if billPayment { raw = "Card bill payment" }
        else if method == .cash { raw = "ATM withdrawal" }
        else if source == .card { raw = txn.description }
        else { raw = merchantName(from: txn.description) ?? merchantName(from: txn.extra) ?? fallbackName(txn.description) }
        // Money moved between your own accounts isn't spending or a payback: the
        // counterparty is the statement's own holder ("UPI-RAHUL VERMA-…",
        // "rahulverma01@…"), unless you've said otherwise for this payee.
        // (Only the counterparty counts — a salary credit names you as receiver.)
        let ownAccount = !billPayment && source == .bank && (MerchantNamer.ownAccount(raw) ?? isHolder(raw, in: txn))
        let named: (name: String, category: ExpenseCategory?) =
            billPayment || method == .cash ? (raw, nil) : MerchantNamer.resolve(raw, context: txn.description)

        return StatementRow(
            date: txn.date,
            description: txn.description,
            merchant: named.name,
            sourceKey: raw,
            amount: txn.amount,
            isCredit: credit,
            category: named.category ?? TransactionParser().inferCategory(from: raw),   // not the narration: "@ptaxis" isn't a taxi
            method: method,
            flag: billPayment ? .cardBillPayment : ownAccount ? .selfTransfer : nil,
            include: !billPayment && !ownAccount
        )
    }

    private func isHolder(_ counterparty: String, in txn: RawTxn) -> Bool {
        guard let holder else { return false }
        let full = holder.joined(), reversed = holder.reversed().joined()
        let party = MerchantNamer.key(counterparty)
        if party.contains(full) || party.contains(reversed) { return true }
        // "UPI-RAHUL" with "VERMA-RAHULVERMA01@…" wrapped onto the next line.
        let narration = MerchantNamer.key(txn.description + " " + txn.extra)
        return party == holder[0] && narration.contains(full)
    }

    /// First two name words of the account holder, from header lines like
    /// "MR RAHUL VERMA" or "Account holder name" + "RAHUL VERMA".
    private func holderName(in lines: [String]) -> [String]? {
        let labels = ["account holder name", "customer name", "account name", "name of the customer"]
        // Header layouts put other labels beside the name ("Account holder name  Account number").
        let labelWords: Set<String> = ["mrs", "miss", "account", "number", "holder", "name", "address", "type",
                                       "branch", "customer", "date", "ifsc", "statement", "mobile", "email", "joint"]
        func nameWords(_ text: String) -> [String] {
            text.split(separator: " ").map { $0.lowercased().filter(\.isLetter) }
                .filter { $0.count >= 3 && !labelWords.contains($0) }
        }
        for (i, line) in lines.prefix(80).enumerated() {
            if let label = labels.lazy.compactMap({ line.range(of: $0, options: .caseInsensitive) }).first {
                // The name follows the label, or sits on the next line.
                for text in [String(line[label.upperBound...])] + lines.dropFirst(i + 1).prefix(1) {
                    let words = nameWords(text)
                    if words.count >= 2 { return Array(words.prefix(2)) }
                }
            } else if line.range(of: #"^(MR|MRS|MS|MISS)\.?\s+[A-Za-z]"#, options: [.regularExpression, .caseInsensitive]) != nil {
                let words = nameWords(line)
                if words.count >= 2 { return Array(words.prefix(2)) }
            }
        }
        return nil
    }

    /// Last resort when neither columns nor balances say which way money moved.
    private func guessCredit(_ description: String) -> Bool {
        let upper = " " + description.uppercased()
        return ["/CR/", " CR ", " CR-", "-CR-", "CREDIT", "SALARY", "REFUND", "INTEREST", "REVERSAL", " BY "].contains(where: upper.contains)
    }

    /// Payee from a bank narration like "UPI/DR/4123…/SWIGGY/YESB/swiggy@ybl"
    /// or "UPI-SWIGGY-SWIGGY@YBL-YESB0000001-…": the first real name before the
    /// VPA, else the VPA's name part.
    private func merchantName(from description: String) -> String? {
        let noise: Set<String> = ["UPI", "DR", "CR", "P2M", "P2A", "P2P", "IMPS", "NEFT", "RTGS", "POS", "ECOM", "ATM", "ATW",
                                  "NWD", "MB", "IB", "INB", "BIL", "ONL", "TO", "BY", "TRANSFER", "TRF", "PAYMENT",
                                  "SENT", "RECEIVED", "FROM", "REF", "TXN", "INR", "PURCHASE", "PCD", "VPS",
                                  "VIN", "MMT", "ACH", "NACH", "OTHERS", "NA"]
        let tokens = description.components(separatedBy: CharacterSet(charactersIn: "/-:|*"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let vpaIndex = tokens.firstIndex { $0.contains("@") }
        for token in tokens[..<(vpaIndex ?? tokens.endIndex)] {
            let words = token.split(separator: " ").map(String.init).filter { word in
                let upper = word.uppercased()
                return !noise.contains(upper) && Self.isWordy(word) && !upper.contains("XX")
                    && upper.range(of: #"^[A-Z]{4}0[A-Z0-9]{6}$"#, options: .regularExpression) == nil
            }
            let name = words.joined(separator: " ")
            if name.filter(\.isLetter).count >= 3 { return name }
        }
        // The handle's name part, read whole: splitting on "-" would turn "9812345678-2@ybl" into "2".
        let joined = description.replacingOccurrences(of: #"([.\-])\s+"#, with: "$1", options: .regularExpression)
        if let match = joined.range(of: #"[A-Za-z0-9._\-]+\s?@"#, options: .regularExpression) {
            let name = joined[match].dropLast().trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"-\d{1,2}$"#, with: "", options: .regularExpression)
            if name.contains(where: { $0.isLetter || $0.isNumber }) { return name }
        }
        return nil
    }

    /// Mostly letters — not a reference/card number like "0000121073049687", "06APR2", "EPR2709".
    private static func isWordy(_ word: String) -> Bool {
        word.filter(\.isNumber).count < max(1, word.filter(\.isLetter).count)
    }

    /// When no payee can be picked out, the readable words of the narration ("IMPS P2P").
    private func fallbackName(_ description: String) -> String {
        let parts = description.components(separatedBy: CharacterSet(charactersIn: " /-:|*")).filter { !$0.isEmpty }
        let words = parts.filter(Self.isWordy).prefix(4)
        if !words.isEmpty { return words.joined(separator: " ") }
        // e.g. a cut-off handle "paytmqr281005050101"
        return parts.filter { $0.contains(where: \.isLetter) }.max { $0.count < $1.count } ?? description
    }

    // MARK: - CSV

    private struct Columns {
        var date: Int, description: Int
        var debit: Int?, credit: Int?, amount: Int?, type: Int?
    }

    private func parseCSV(_ text: String, source: StatementSource) -> [RawTxn] {
        let lines = text.components(separatedBy: .newlines)
        holder = holderName(in: lines.map { $0.replacingOccurrences(of: ",", with: " ") })
        let sample = lines.prefix(40).joined()
        let delimiter: Character = sample.filter { $0 == "\t" }.count > sample.filter { $0 == "," }.count ? "\t" : ","
        let rows = lines.map { splitCSVLine($0, delimiter: delimiter) }

        // Statements often start with account details; the header is the first
        // row naming a date, a description and amount column(s).
        guard let headerIndex = rows.firstIndex(where: { columns(in: $0) != nil }),
              let cols = columns(in: rows[headerIndex]) else { return [] }

        var result: [RawTxn] = []
        for row in rows[(headerIndex + 1)...] {
            func cell(_ i: Int?) -> String? { i.flatMap { $0 < row.count ? row[$0] : nil } }
            guard let dateText = cell(cols.date), let date = parseDate(dateText),
                  let description = cell(cols.description).map(clean), !description.isEmpty else { continue }

            if cols.debit != nil || cols.credit != nil {
                if let debit = cell(cols.debit).flatMap(parseAmount), debit.value > 0 {
                    result.append(RawTxn(date: date, description: description, amount: debit.value, isCredit: false))
                } else if let credit = cell(cols.credit).flatMap(parseAmount), credit.value > 0 {
                    result.append(RawTxn(date: date, description: description, amount: credit.value, isCredit: true))
                }
            } else if let amount = cell(cols.amount).flatMap(parseAmount), amount.value > 0 {
                let isCredit: Bool
                if let type = cell(cols.type)?.trimmingCharacters(in: .whitespaces).lowercased(), !type.isEmpty {
                    isCredit = type.hasPrefix("c")
                } else if let marked = amount.markedCredit {
                    isCredit = marked
                } else {
                    // Signed single column: cards show payments/refunds negative,
                    // bank accounts show withdrawals negative.
                    isCredit = source == .card ? amount.negative : !amount.negative
                }
                result.append(RawTxn(date: date, description: description, amount: amount.value, isCredit: isCredit))
            }
        }
        return result
    }

    private func columns(in header: [String]) -> Columns? {
        let h = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func find(_ match: (String) -> Bool) -> Int? { h.indices.first { match(h[$0]) } }

        guard let date = find({ $0.contains("date") && !$0.contains("value") }) ?? find({ $0.contains("date") }),
              let description = find({ c in ["narration", "description", "particular", "details", "remark"].contains(where: c.contains) })
        else { return nil }

        // A "Dr/Cr" style column says the direction; it isn't an amount column.
        let type = find { $0.contains("dr/cr") || $0.contains("cr/dr") || $0.contains("debit/credit") || $0 == "type" }
        let debit = h.indices.first { $0 != type && (h[$0].contains("withdraw") || h[$0].contains("debit") || h[$0] == "dr") }
        let credit = h.indices.first { $0 != type && (h[$0].contains("deposit") || h[$0].contains("credit") || h[$0] == "cr") }
        let amount = h.indices.first { $0 != debit && $0 != credit && (h[$0].contains("amount") || h[$0] == "amt") }

        // Separate withdrawal/deposit columns win; otherwise one (signed or typed) amount column.
        if let debit, let credit {
            return Columns(date: date, description: description, debit: debit, credit: credit, amount: nil, type: nil)
        }
        guard let amount else { return nil }
        return Columns(date: date, description: description, debit: nil, credit: nil, amount: amount, type: type)
    }

    private func splitCSVLine(_ line: String, delimiter: Character) -> [String] {
        var cells: [String] = [], current = "", quoted = false
        for ch in line {
            if ch == "\"" { quoted.toggle() }
            else if ch == delimiter && !quoted { cells.append(current); current = "" }
            else { current.append(ch) }
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - PDF

    private let amountRegex = try! NSRegularExpression(
        pattern: #"(?<![\d.,])((?:\d{1,3}(?:,\d{2,3})+|\d+)\.\d{2})(?![\d.])(?:\s?(cr|dr)\b)?"#,
        options: .caseInsensitive)

    private func parsePDF(_ doc: PDFDocument, source: StatementSource) -> [RawTxn] {
        let lines = (0..<doc.pageCount).compactMap { doc.page(at: $0) }.flatMap(visualLines)
        holder = holderName(in: lines)

        var openingBalance: Double?
        if let line = lines.first(where: { $0.lowercased().contains("opening balance") }) {
            openingBalance = amountTokens(in: line).last?.value
        }

        // A row starts on a line that begins with a date (after an optional serial
        // number). Lines in between are wrapped narration, kept as context.
        struct Row { let date: Date; let body: String; let before: [String]; var after: [String] = [] }
        var rows: [Row] = []
        var loose: [String] = []
        for line in lines {
            if let (date, body) = rowStart(line) {
                rows.append(Row(date: date, body: body, before: loose))
                loose = []
            } else {
                if !rows.isEmpty { rows[rows.count - 1].after.append(line) }
                loose.append(line)
            }
        }

        var txns: [RawTxn] = []
        for var row in rows {
            // A long narration can push the row's amounts onto the line below.
            if amountTokens(in: row.body).isEmpty, let next = row.after.first, !amountTokens(in: next).isEmpty {
                row = Row(date: row.date, body: row.body + " " + next, before: row.before, after: Array(row.after.dropFirst()))
            }
            let amounts = amountTokens(in: row.body)
            guard let first = amounts.first else { continue }   // a header/summary date, not a transaction
            let wrapped = descriptionText(row.after.prefix(2).joined(separator: " "))
            var description = descriptionText(String(row.body[..<first.range.lowerBound]))
            // Some layouts centre the row vertically, leaving its narration on the lines just around it.
            if description.filter(\.isLetter).count < 3 {
                let below = row.after.prefix(1).filter { $0.count < 60 }   // not a page footer
                description = descriptionText((row.before.suffix(1) + below + [description]).joined(separator: " "))
            }
            let lower = description.lowercased()
            guard description.contains(where: \.isLetter),
                  !["opening balance", "closing balance", "brought forward", "b/f"].contains(where: lower.contains) else { continue }
            // Empty Debit/Credit columns printed as "-": "- 102.00 …" is a credit, "260.00 - …" a debit.
            let hint: Bool? = row.body[..<first.range.lowerBound].range(of: #"(^|\s)-\s*$"#, options: .regularExpression) != nil ? true
                : row.body[first.range.upperBound...].range(of: #"^\s*-(\s|$)"#, options: .regularExpression) != nil ? false : nil

            if source == .card {
                // Amount is the last number (reward points come before it). "Cr", or a
                // "+" right before the amount ("+ ₹ 2.00"), marks payments and refunds.
                let amount = amounts[amounts.count - 1]
                let plus = row.body[..<amount.range.lowerBound]
                    .range(of: #"\+\s*(?:C|₹|Rs\.?|INR)?\s*$"#, options: .regularExpression) != nil
                txns.append(RawTxn(date: row.date, description: description, amount: amount.value,
                                   isCredit: amount.markedCredit ?? plus, extra: wrapped))
            } else if amounts.count >= 3, amounts[0].value == 0 || amounts[1].value == 0 {
                // Withdrawal, deposit and balance all printed (one of them 0.00).
                let isCredit = amounts[0].value == 0
                txns.append(RawTxn(date: row.date, description: description,
                                   amount: isCredit ? amounts[1].value : amounts[0].value,
                                   isCredit: isCredit, balance: amounts[2].value, extra: wrapped))
            } else {
                // Amount then running balance; direction comes from how the balance moved.
                txns.append(RawTxn(date: row.date, description: description, amount: first.value,
                                   isCredit: first.markedCredit, balance: amounts.count > 1 ? amounts[1].value : nil,
                                   extra: wrapped, hint: hint))
            }
        }
        resolveDirections(&txns, openingBalance: openingBalance)
        return txns
    }

    /// The page's text as it looks: PDFKit's text order often runs down columns
    /// (all dates, then all narrations…), so rebuild rows from line fragments'
    /// positions — same height means same row, ordered left to right.
    private func visualLines(of page: PDFPage) -> [String] {
        // PDFKit sometimes merges whole rows into one "line"; a date right after an
        // amount ("… 230.00 10,320.00 14/11/2026 UPI…") can only be the next row.
        positionedLines(of: page).flatMap { line in
            line.replacingOccurrences(of: #"(\d\.\d\d(?:\s?(?:cr|dr)\b)?)\s+("# + Self.datePattern + #")(?![\d/\-.])"#,
                                      with: "$1\n$2", options: [.regularExpression, .caseInsensitive])
                .components(separatedBy: "\n")
        }
    }

    private func positionedLines(of page: PDFPage) -> [String] {
        guard let all = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        var fragments: [(text: String, rect: CGRect)] = all.selectionsByLine().compactMap { selection in
            guard let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return (text, selection.bounds(for: page))
        }
        fragments.sort { $0.rect.midY > $1.rect.midY }

        var rows: [[(text: String, rect: CGRect)]] = []
        for fragment in fragments {
            if let anchor = rows.last?.first,
               abs(anchor.rect.midY - fragment.rect.midY) < min(anchor.rect.height, fragment.rect.height) * 0.5 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            var line = ""
            var previous: CGRect?
            for fragment in row.sorted(by: { $0.rect.minX < $1.rect.minX }) {
                // Touching fragments are one word that PDFKit split ("10,8" + "23.43").
                if let previous { line += fragment.rect.minX - previous.maxX > 1.5 ? " " : "" }
                line += fragment.text
                previous = fragment.rect
            }
            // Re-join amounts split around a separator: "7 ,200.00", "10, 146.89", "2,167 . 14".
            return line.replacingOccurrences(of: #"(\d)\s*([.,])\s*(\d)"#, with: "$1$2$3", options: .regularExpression)
        }
    }

    /// Date and remaining text when a line opens a transaction row. Skips a
    /// repeated value date and a time ("24/08/2026| 20:23 …").
    private func rowStart(_ line: String) -> (Date, String)? {
        guard let match = rowStartRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let dateRange = Range(match.range(at: 1), in: line), let fullRange = Range(match.range, in: line),
              let date = parseDate(String(line[dateRange])) else { return nil }
        var body = String(line[fullRange.upperBound...])
        while true {
            body = body.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "|")))
            if let (_, rest) = splitLeadingDate(body) { body = rest; continue }
            if let time = body.range(of: #"^\d{1,2}:\d{2}(?::\d{2})?"#, options: .regularExpression) {
                body = String(body[time.upperBound...]); continue
            }
            return (date, body)
        }
    }

    /// Narration without dates, times, or trailing reward points / currency marks.
    private func descriptionText(_ text: String) -> String {
        var t = text.replacingOccurrences(of: Self.datePattern, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#, with: " ", options: .regularExpression)
        var words = clean(t).split(separator: " ").map(String.init)
        while let last = words.last, ["+", "-", "C", "₹", "|"].contains(last) || Int(last) != nil { words.removeLast() }
        t = words.joined(separator: " ")
        return t
    }

    /// Fill in credit/debit from running balances. Works whether the statement
    /// lists oldest-first or newest-first (whichever fits the numbers better).
    private func resolveDirections(_ txns: inout [RawTxn], openingBalance: Double?) {
        let idx = txns.indices.filter { txns[$0].balance != nil }
        let pairs = Array(zip(idx, idx.dropFirst()))
        var forward = 0, reverse = 0
        for (a, b) in pairs {
            let delta = abs(txns[b].balance! - txns[a].balance!)
            if abs(delta - txns[b].amount) < 0.01 { forward += 1 }
            if abs(delta - txns[a].amount) < 0.01 { reverse += 1 }
        }
        let oldestFirst = forward >= reverse
        for (a, b) in pairs {
            if oldestFirst, txns[b].isCredit == nil { txns[b].isCredit = txns[b].balance! > txns[a].balance! }
            if !oldestFirst, txns[a].isCredit == nil { txns[a].isCredit = txns[a].balance! > txns[b].balance! }
        }
        // The oldest row compares against the opening balance, if one is printed and adds up.
        if let openingBalance, let oldest = oldestFirst ? idx.first : idx.last, txns[oldest].isCredit == nil,
           abs(abs(txns[oldest].balance! - openingBalance) - txns[oldest].amount) < 0.01 {
            txns[oldest].isCredit = txns[oldest].balance! > openingBalance
        }
    }

    private func amountTokens(in text: String) -> [(value: Double, markedCredit: Bool?, range: Range<String.Index>)] {
        amountRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text), let numRange = Range(match.range(at: 1), in: text),
                  let value = Double(text[numRange].replacingOccurrences(of: ",", with: "")) else { return nil }
            let mark = Range(match.range(at: 2), in: text).map { text[$0].lowercased() == "cr" }
            return (value, mark, range)
        }
    }

    // MARK: - Shared helpers

    private static let month = "(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)"
    private static let datePattern = #"(?:\d{1,2}[/\-.](?:\d{1,2}|"# + month + #")[/\-.]\d{2,4}|\d{1,2} "# + month + #",? \d{2,4}|\d{4}-\d{2}-\d{2})"#
    private let leadingDateRegex = try! NSRegularExpression(pattern: "^" + datePattern, options: .caseInsensitive)
    private let rowStartRegex = try! NSRegularExpression(pattern: #"^(?:\d{1,4}\s+)?("# + datePattern + #")(?![\d/\-.])"#,
                                                         options: .caseInsensitive)

    private func splitLeadingDate(_ text: String) -> (String, String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = leadingDateRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range, in: trimmed) else { return nil }
        return (String(trimmed[range]), String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    /// Indian statement dates (day first). Stored at noon IST so the calendar
    /// day never shifts.
    private func parseDate(_ text: String) -> Date? {
        guard let (dateText, _) = splitLeadingDate(text) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ist
        let formats = ["dd/MM/yyyy", "dd/MM/yy", "dd-MM-yyyy", "dd-MM-yy", "dd.MM.yyyy", "dd.MM.yy",
                       "dd-MMM-yyyy", "dd-MMM-yy", "dd/MMM/yyyy", "dd/MMM/yy", "dd MMM yyyy", "dd MMM yy",
                       "dd MMM, yyyy", "yyyy-MM-dd"]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateText) {
                // "yyyy" happily reads "26" as year 26 — reject and try the next format.
                let year = Calendar(identifier: .gregorian).component(.year, from: date)
                if (2000...2100).contains(year) { return date.addingTimeInterval(12 * 3600) }
            }
        }
        return nil
    }

    private func parseAmount(_ text: String) -> (value: Double, markedCredit: Bool?, negative: Bool)? {
        var s = text.lowercased()
            .replacingOccurrences(of: "₹", with: "")
            .replacingOccurrences(of: "inr", with: "")
            .replacingOccurrences(of: "rs.", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        var marked: Bool?
        if s.hasSuffix("cr") { marked = true; s.removeLast(2) } else if s.hasSuffix("dr") { marked = false; s.removeLast(2) }
        s = s.trimmingCharacters(in: .whitespaces)
        var negative = s.hasPrefix("-")
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        guard let value = Double(s.replacingOccurrences(of: "-", with: "")) else { return nil }
        return (abs(value), marked, negative)
    }

    private func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
    }
}
