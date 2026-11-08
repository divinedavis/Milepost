import Foundation
import Observation
import Security

/// Neutral age screen asked before a NEW friends account is used (COPPA,
/// 2026-11-07). Milepost's only account is the optional friends layer, made
/// by Sign in with Apple, so "account creation" is a first-time Apple
/// sign-in. Recording never needs an account and is never gated. Adapted
/// from Barrel Baseball (Baseball-Stat-Tracker b3bdafe) and Hidden Gems
/// (1ad5b39).
///
/// Rules this file encodes:
///  - Birth month + year, nothing pre-selected, no hint of the required age.
///    The answer never leaves the phone; the account gets only
///    `age_confirmed_13_plus = true` in its Supabase auth user_metadata.
///  - Only month + year are asked, so in the birth month itself we cannot
///    tell whether the birthday has passed: treat it as not yet passed.
///  - An under-13 answer is remembered in UserDefaults AND the Keychain
///    (Keychain items survive a reinstall), so going back, or deleting and
///    reinstalling the app, does not get round it.
///  - Accounts that existed before the gate are never asked: "new" is decided
///    from the auth server's own timestamps.
enum AgeGate {
    static let minimumAge = 13
    /// Supabase auth user_metadata key set on accounts that passed the gate.
    static let metadataKey = "age_confirmed_13_plus"
    /// A Sign in with Apple session counts as account creation when the
    /// account's latest sign-in is (within this window of) its creation. Both
    /// timestamps come from the auth server, so a wrong phone clock cannot
    /// move an account in or out of the gate.
    static let newAccountWindow: TimeInterval = 120

    /// Whole years old on `date`, given birth month (1...12) and year.
    static func age(birthYear: Int, birthMonth: Int, on date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return 0 }
        var years = year - birthYear
        // The birthday this year has passed only once we're past the birth month.
        if month <= birthMonth { years -= 1 }
        return max(0, years)
    }

    static func isOldEnough(birthYear: Int, birthMonth: Int, on date: Date = .now, calendar: Calendar = .current) -> Bool {
        age(birthYear: birthYear, birthMonth: birthMonth, on: date, calendar: calendar) >= minimumAge
    }

    /// Years offered in the picker: this year back 100 years, newest first.
    /// Starting at the current year means no option implies an answer.
    static func selectableYears(now: Date = .now, calendar: Calendar = .current) -> [Int] {
        let current = calendar.component(.year, from: now)
        return Array(stride(from: current, through: current - 100, by: -1))
    }

    /// Whether a just-completed Sign in with Apple created a brand-new account
    /// that still has to answer. Existing accounts (signing in is not account
    /// creation) and accounts that already confirmed go straight through.
    static func needsAgeCheck(_ account: SessionAccount) -> Bool {
        if account.ageConfirmed { return false }
        let latest = account.lastSignInAt ?? account.createdAt
        return abs(latest.timeIntervalSince(account.createdAt)) <= newAccountWindow
    }
}

/// What the auth server says about the signed-in account, read from the
/// session it returned.
struct SessionAccount: Equatable {
    let id: UUID
    let createdAt: Date
    let lastSignInAt: Date?
    let ageConfirmed: Bool
}

/// Persistence for the device-level age-gate values. The production store is
/// the Keychain; tests inject an in-memory one, and UI tests a file, because
/// an unsigned simulator build has no Keychain entitlement.
protocol AgeGatePersistentStore {
    func string(for key: String) -> String?
    func set(_ value: String, for key: String)
    func remove(_ key: String)
}

/// Keychain-backed store: generic-password items under one service,
/// `AfterFirstUnlock` so the block also travels in an encrypted backup to a
/// new phone. Not synchronizable (no iCloud Keychain): it is about this device.
struct KeychainAgeGateStore: AgeGatePersistentStore {
    var service = "com.divinedavis.milepost.agegate"

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func string(for key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, for key: String) {
        remove(key)
        var query = baseQuery(key)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}

/// In memory, for unit tests (and a stand-in "Keychain" that outlives the
/// UserDefaults wipe a reinstall test simulates).
final class MemoryAgeGateStore: AgeGatePersistentStore {
    private var values: [String: String] = [:]
    func string(for key: String) -> String? { values[key] }
    func set(_ value: String, for key: String) { values[key] = value }
    func remove(_ key: String) { values[key] = nil }
}

#if DEBUG
/// UI tests: the runner-launched app cannot write the Keychain, and `-uitest`
/// wipes UserDefaults at every launch, so a small file in Application Support
/// plays the Keychain's part (it outlives a relaunch like the Keychain
/// outlives a reinstall). Wiped at launch unless `-uitest-keep-agegate`.
struct FileAgeGateStore: AgeGatePersistentStore {
    static let url = URL.applicationSupportDirectory.appendingPathComponent("uitest-agegate.json")

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: Self.url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func save(_ values: [String: String]) {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(values).write(to: Self.url, options: .atomic)
    }

    func string(for key: String) -> String? { load()[key] }
    func set(_ value: String, for key: String) { var v = load(); v[key] = value; save(v) }
    func remove(_ key: String) { var v = load(); v[key] = nil; save(v) }
    static func wipe() { try? FileManager.default.removeItem(at: url) }
}
#endif

/// Remembers an under-13 answer on this phone, and the id of a new account
/// still waiting for its answer (so killing the app mid-question does not let
/// that account in on the next launch).
@MainActor
@Observable
final class AgeGateStore {
    static let blockedKey = "ageGate.blocked.v1"
    static let pendingUserKey = "ageGate.pendingUserId.v1"

    private(set) var isBlocked: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistent: AgeGatePersistentStore

    init(defaults: UserDefaults = .standard, persistent: AgeGatePersistentStore = KeychainAgeGateStore()) {
        self.defaults = defaults
        self.persistent = persistent
        let blocked = persistent.string(for: Self.blockedKey) != nil || defaults.bool(forKey: Self.blockedKey)
        isBlocked = blocked
        // Re-sync both stores so a reinstall (defaults wiped, Keychain kept)
        // carries the block in both places again.
        if blocked { persistBlock() }
    }

    func recordBlocked() {
        isBlocked = true
        persistBlock()
    }

    private func persistBlock() {
        defaults.set(true, forKey: Self.blockedKey)
        persistent.set("1", for: Self.blockedKey)
    }

    /// The new account waiting on the age question, if any.
    var pendingUserID: UUID? {
        let raw = defaults.string(forKey: Self.pendingUserKey) ?? persistent.string(for: Self.pendingUserKey)
        return raw.flatMap(UUID.init(uuidString:))
    }

    func setPendingUser(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: Self.pendingUserKey)
            persistent.set(id.uuidString, for: Self.pendingUserKey)
        } else {
            defaults.removeObject(forKey: Self.pendingUserKey)
            persistent.remove(Self.pendingUserKey)
        }
    }
}
