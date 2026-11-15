//
//  MerchantNamer.swift
//  Expense Tracker
//
//  Turns raw payees from bank text ("ZOMATOGURGAON", "uberindiasystem1872",
//  "9812345678") into a readable name and category: what you've taught it
//  first, then a built-in list of common Indian merchants, then light tidying.
//

import Foundation

enum MerchantNamer {
    struct Rule: Codable {
        var name: String?          // set only for payees the built-in list doesn't know
        var category: ExpenseCategory
        var ownAccount: Bool?      // your call on "transfer to my own account"; nil = not decided
        var notSpending: Bool?     // money sent to them isn't your spending (e.g. family); nil = not decided
    }

    private static let rulesKey = "MerchantRules"

    /// Lower-case letters and digits only, so "ZOMATO GURGAON" and "zomatogurgaon" match.
    static func key(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Name and category for a raw payee. `context` (e.g. the full bank narration)
    /// is also searched for a known merchant when the payee itself isn't one.
    static func resolve(_ raw: String, context: String = "") -> (name: String, category: ExpenseCategory?) {
        let known = knownMerchant(in: key(raw)) ?? knownMerchant(in: key(context))
        if let rule = rules[key(raw)] {
            return (rule.name ?? known?.name ?? tidy(raw), rule.category)
        }
        if let known { return (known.name ?? tidy(raw), known.category) }
        return (tidy(raw), nil)
    }

    /// True when the built-in list names this payee (so a manual title is a
    /// one-off, not a name to remember).
    static func isKnown(_ raw: String) -> Bool { knownMerchant(in: key(raw))?.name != nil }

    /// Remember your choice for this payee; future imports and captures use it.
    /// Whether you've marked this payee as one of your own accounts (nil if never said).
    static func ownAccount(_ raw: String) -> Bool? { rules[key(raw)]?.ownAccount }

    /// Whether you've said money sent to this payee isn't your spending (nil if never said).
    static func notSpending(_ raw: String) -> Bool? { rules[key(raw)]?.notSpending }

    static func learn(_ raw: String, name: String?, category: ExpenseCategory, ownAccount: Bool? = nil, notSpending: Bool? = nil) {
        var all = rules
        all[key(raw)] = Rule(name: isKnown(raw) ? nil : name, category: category,
                             ownAccount: ownAccount ?? all[key(raw)]?.ownAccount,
                             notSpending: notSpending ?? all[key(raw)]?.notSpending)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }

    private static var rules: [String: Rule] {
        guard let data = UserDefaults.standard.data(forKey: rulesKey),
              let decoded = try? JSONDecoder().decode([String: Rule].self, from: data) else { return [:] }
        return decoded
    }

    private static func knownMerchant(in compact: String) -> (name: String?, category: ExpenseCategory)? {
        guard !compact.isEmpty else { return nil }
        return known.first { entry in entry.patterns.contains { compact.contains($0) } }
            .map { ($0.name, $0.category) }
    }

    /// Unknown payees: drop a gateway prefix ("PYU*") and a trailing city, and
    /// title-case shouty bank text. Handles like "paytmqr6ktqsd" stay as they are.
    private static func tidy(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: #"^(?:EMI\s+)?(?:[A-Za-z]{2,5}\*)?"#, with: "", options: .regularExpression)
        for city in cities {
            // Long city names can be glued on ("ZOMATOGURGAON"); "IN" only as its own word.
            let pattern = (city.count > 2 ? "\\s*" : "\\s+") + city + "$"
            if let range = name.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
               range.lowerBound > name.startIndex {
                name.removeSubrange(range)
                break
            }
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return raw }
        return name.contains(where: \.isLowercase) ? name : name.capitalized
    }

    private static let cities = ["NEW DELHI", "DELHI", "GURUGRAM", "GURGAON", "NOIDA", "BANGALORE", "BENGALURU",
                                 "MUMBAI", "CHENNAI", "HYDERABAD", "PUNE", "KOLKATA", "AHMEDABAD", "JAIPUR",
                                 "CHANDIGARH", "LUCKNOW", "IN"]

    /// Ordered: more specific patterns first ("swiggyinstamart" before "swiggy",
    /// "jiofinancial" before "jio"). A nil name is a generic keyword ("pharmacy"):
    /// it sets the category but keeps the payee's own name.
    private static let known: [(patterns: [String], name: String?, category: ExpenseCategory)] = [
        // Quick commerce & grocery
        (["swiggyinstamart", "instamart"], "Swiggy Instamart", .quickCommerce),
        (["blinkit", "blinkcommerce", "grofers"], "Blinkit", .quickCommerce),
        (["zepto"], "Zepto", .quickCommerce),
        (["bbnow"], "BigBasket Now", .quickCommerce),
        (["flipkartminutes"], "Flipkart Minutes", .quickCommerce),
        (["dunzo"], "Dunzo", .quickCommerce),
        (["bigbasket", "supermarketgrocery"], "BigBasket", .grocery),
        (["dmart", "avenuesupermart"], "DMart", .grocery),
        (["jiomart"], "JioMart", .grocery),
        (["reliancefresh", "smartbazaar", "reliancesmart", "reliancretail"], "Reliance Retail", .grocery),
        (["naturesbasket"], "Nature's Basket", .grocery),
        // Food
        (["swiggy"], "Swiggy", .food),
        (["zomato"], "Zomato", .food),
        (["districtdining"], "District (dining)", .food),
        (["eatsure", "faasos", "behrouz", "box8"], "EatSure", .food),
        (["mcdonald"], "McDonald's", .food),
        (["dominos", "jubilantfood"], "Domino's", .food),
        (["pizzahut"], "Pizza Hut", .food),
        (["burgerking"], "Burger King", .food),
        (["sapphirekfc", "kfc"], "KFC", .food),
        (["starbucks", "tatastarbucks"], "Starbucks", .food),
        (["chaayos"], "Chaayos", .food),
        (["haldiram"], "Haldiram's", .food),
        (["bikanervala"], "Bikanervala", .food),
        (["californiaburrito"], "California Burrito", .food),
        (["theobroma"], "Theobroma", .food),
        (["subway"], "Subway", .food),
        (["dunkin"], "Dunkin'", .food),
        (["bobabhai"], "Boba Bhai", .food),
        (["standardice"], "Standard Ice Cream", .food),
        // Transport & travel
        (["uberindia", "uber"], "Uber", .transportation),
        (["rapido", "roppen"], "Rapido", .transportation),
        (["olacabs", "anitechnologies"], "Ola", .transportation),
        (["delhimetro", "dmrc", "metrorail", "mumbaimetro", "bmrcl"], "Metro", .transportation),
        (["irctc"], "IRCTC", .transportation),
        (["yulu"], "Yulu", .transportation),
        (["cityflo"], "Cityflo", .transportation),
        (["redbus"], "redBus", .transportation),
        (["makemytrip"], "MakeMyTrip", .transportation),
        (["goibibo"], "Goibibo", .transportation),
        (["ixigo"], "ixigo", .transportation),
        (["cleartrip"], "Cleartrip", .transportation),
        (["interglobe", "indigo"], "IndiGo", .transportation),
        (["airindia"], "Air India", .transportation),
        (["fastag", "nationalhighway"], "Tolls / FASTag", .transportation),
        (["indianoil", "iocl", "hpcl", "bpcl", "bharatpetroleum", "shellindia", "petrol", "fuel"], nil, .transportation),
        // Shopping
        (["smartbuy", "gyftr"], "Gift voucher (SmartBuy)", .shopping),
        (["amazon", "amzn"], "Amazon", .shopping),
        (["flipkart"], "Flipkart", .shopping),
        (["myntra"], "Myntra", .shopping),
        (["ajio"], "AJIO", .shopping),
        (["nykaa"], "Nykaa", .shopping),
        (["meesho"], "Meesho", .shopping),
        (["decathlon"], "Decathlon", .shopping),
        (["lenskart"], "Lenskart", .shopping),
        (["tatacliq"], "Tata CLiQ", .shopping),
        (["croma"], "Croma", .shopping),
        (["ikea"], "IKEA", .shopping),
        (["tanishq"], "Tanishq", .shopping),
        // Entertainment & subscriptions
        (["netflix"], "Netflix", .entertainment),
        (["spotify"], "Spotify", .entertainment),
        (["jiohotstar", "hotstar", "jiocinema"], "JioHotstar", .entertainment),
        (["primevideo"], "Prime Video", .entertainment),
        (["youtube"], "YouTube", .entertainment),
        (["bookmyshow"], "BookMyShow", .entertainment),
        (["pvrinox", "pvrcinema", "inoxleisure"], "PVR INOX", .entertainment),
        (["sonyliv"], "SonyLIV", .entertainment),
        (["googleplay"], "Google Play", .entertainment),
        (["appleservices", "itunes", "applecombill"], "Apple", .entertainment),
        // Bills
        (["googleindia", "googleclouds", "googleworkspace"], "Google", .bills),
        (["airtel"], "Airtel", .bills),
        (["jiofinancial"], "Jio Financial Services", .investment),
        (["reliancejio", "jioprepaid", "jiopostpaid"], "Jio", .bills),
        (["vodafone", "vodaidea"], "Vi", .bills),
        (["bses", "tatapower", "adanielectric", "electricity"], nil, .bills),
        (["indraprasthagas", "mahanagargas", "gasbill"], nil, .bills),
        (["actfibernet", "broadband"], nil, .bills),
        (["dcardfee", "annualfee"], "Card fee", .bills),
        // Health & fitness
        (["apollo"], "Apollo", .healthcare),
        (["pharmeasy"], "PharmEasy", .healthcare),
        (["netmeds"], "Netmeds", .healthcare),
        (["tata1mg", "1mg"], "Tata 1mg", .healthcare),
        (["medplus"], "MedPlus", .healthcare),
        (["practo"], "Practo", .healthcare),
        (["cultfit", "curefit"], "cult.fit", .healthcare),
        (["pharmacy", "chemist", "medicine", "hospital", "clinic"], nil, .healthcare),
        (["fitness", "gym"], nil, .healthcare),
        // Education
        (["coursera"], "Coursera", .education),
        (["udemy"], "Udemy", .education),
        (["unacademy"], "Unacademy", .education),
        (["datascience"], "BS in Data Science", .education),
        // Investments
        (["groww"], "Groww", .investment),
        (["zerodha"], "Zerodha", .investment),
        (["upstox"], "Upstox", .investment),
        (["indianclearing", "iccl"], "Mutual fund SIP (ICCL)", .investment),
        (["paytmmoney"], "Paytm Money", .investment),
        (["etmoney"], "ET Money", .investment),
        (["nippon"], "Nippon India MF", .investment),
        // Other
        (["intpd", "interestpaid", "interestcredit"], "Interest", .other),
    ]
}
