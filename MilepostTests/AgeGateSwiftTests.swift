import Foundation
import Testing
@testable import Milepost

/// The neutral age question asked before a new friends account is used
/// (COPPA, 2026-11-07). See Milepost/Social/AgeGate.swift.
@Suite("Age gate")
struct AgeGateSwiftTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int = 15) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("Whole years, with the birth month itself counted as not yet passed",
          arguments: [
              // (birth year, birth month, today's year, today's month, age)
              (2013, 11, 2026, 11, 12),   // birth month: birthday treated as not passed
              (2013, 10, 2026, 11, 13),   // month after: 13
              (2013, 12, 2026, 11, 12),
              (2014, 1, 2026, 11, 12),
              (1991, 12, 2026, 11, 34),
              (2026, 11, 2026, 11, 0),    // never negative
          ])
    func ageMath(birthYear: Int, birthMonth: Int, year: Int, month: Int, expected: Int) {
        #expect(AgeGate.age(birthYear: birthYear, birthMonth: birthMonth, on: date(year, month), calendar: utc) == expected)
    }

    @Test("13 is the line: 12 is refused, 13 and older pass")
    func threshold() {
        let now = date(2026, 11)
        #expect(!AgeGate.isOldEnough(birthYear: 2013, birthMonth: 11, on: now, calendar: utc))
        #expect(AgeGate.isOldEnough(birthYear: 2013, birthMonth: 10, on: now, calendar: utc))
        #expect(AgeGate.isOldEnough(birthYear: 1980, birthMonth: 1, on: now, calendar: utc))
        #expect(AgeGate.minimumAge == 13)
    }

    @Test("The year list starts at this year, so no option hints at an answer")
    func neutralYears() {
        let years = AgeGate.selectableYears(now: date(2026, 11), calendar: utc)
        #expect(years.first == 2026)
        #expect(years.last == 1926)
        #expect(years.count == 101)
        #expect(years == years.sorted(by: >))
    }

    @Test("Only a brand-new, unconfirmed account is asked",
          arguments: [
              (0.0, false, true),         // created and signed in together: new
              (90.0, false, true),        // within the window
              (3600.0, false, false),     // an existing account signing in again
              (0.0, true, false),         // already confirmed
          ])
    func newAccountRule(secondsSinceCreation: Double, confirmed: Bool, asked: Bool) {
        let created = date(2026, 11)
        let account = SessionAccount(id: UUID(), createdAt: created,
                                     lastSignInAt: created.addingTimeInterval(secondsSinceCreation),
                                     ageConfirmed: confirmed)
        #expect(AgeGate.needsAgeCheck(account) == asked)
    }

    @Test("Only the yes/no flag is ever written, under the agreed key")
    func metadataKey() {
        #expect(AgeGate.metadataKey == "age_confirmed_13_plus")
    }
}

/// The device-level block and the account held for the question.
@MainActor
@Suite("Age gate device block")
struct AgeGateDeviceTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "AgeGateDeviceTests.\(UUID().uuidString)")!
    }

    @Test("An under-13 answer survives a reinstall (defaults wiped, Keychain kept)")
    func blockSurvivesReinstall() {
        let keychain = MemoryAgeGateStore()
        let first = AgeGateStore(defaults: defaults(), persistent: keychain)
        #expect(!first.isBlocked)
        first.recordBlocked()
        let reinstalled = defaults()
        let second = AgeGateStore(defaults: reinstalled, persistent: keychain)
        #expect(second.isBlocked)
        // and is written back into the fresh defaults too
        #expect(reinstalled.bool(forKey: AgeGateStore.blockedKey))
    }

    @Test("The held account id is kept in both stores and cleared from both")
    func pendingAccount() {
        let keychain = MemoryAgeGateStore()
        let d = defaults()
        let store = AgeGateStore(defaults: d, persistent: keychain)
        let id = UUID()
        store.setPendingUser(id)
        #expect(AgeGateStore(defaults: defaults(), persistent: keychain).pendingUserID == id)
        store.setPendingUser(nil)
        #expect(store.pendingUserID == nil)
        #expect(keychain.string(for: AgeGateStore.pendingUserKey) == nil)
    }

    // MARK: The sign-in flow, against the in-memory backend

    private func make(_ setUp: (DemoSocialBackend) -> Void = { _ in },
                      keychain: MemoryAgeGateStore = MemoryAgeGateStore(),
                      blocked: Bool = false,
                      pending: UUID? = nil) -> (SocialStore, DemoSocialBackend, AgeGateStore) {
        let d = defaults()
        let backend = DemoSocialBackend()
        setUp(backend)
        let gate = AgeGateStore(defaults: d, persistent: keychain)
        if blocked { gate.recordBlocked() }
        if let pending { gate.setPendingUser(pending) }
        return (SocialStore(backend: backend, defaults: d, ageGate: gate), backend, gate)
    }

    @Test("An existing account signs in without being asked")
    func existingAccountGoesStraightIn() async {
        let (s, backend, gate) = make { $0.startSignedOut() }
        await s.completeSignIn(idToken: "t", nonce: nil)
        #expect(s.phase == .signedIn)
        #expect(!s.ageCheckPending)
        #expect(gate.pendingUserID == nil)
        #expect(backend.deletedAccounts == 0)
    }

    @Test("A new account is held, signed out, until it answers")
    func newAccountIsHeld() async {
        let (s, _, gate) = make { $0.startSignedOut(); $0.nextSignInCreatesAccount = true }
        await s.completeSignIn(idToken: "t", nonce: nil)
        #expect(s.ageCheckPending)
        #expect(s.phase == .signedOut)
        #expect(!s.canUseFriends)
        #expect(gate.pendingUserID == DemoSocialBackend.me)
    }

    @Test("13+ records only the flag and lets the account in")
    func oldEnoughContinues() async {
        let (s, backend, gate) = make { $0.startSignedOut(); $0.nextSignInCreatesAccount = true }
        await s.completeSignIn(idToken: "t", nonce: nil)
        await s.answerAge(oldEnough: true)
        #expect(backend.ageConfirmed)
        #expect(s.phase == .signedIn)
        #expect(!s.ageCheckPending)
        #expect(gate.pendingUserID == nil)
        #expect(!gate.isBlocked)
    }

    @Test("Under 13 deletes the new account and blocks the phone")
    func underThirteenIsBlocked() async {
        let (s, backend, gate) = make { $0.startSignedOut(); $0.nextSignInCreatesAccount = true }
        await s.completeSignIn(idToken: "t", nonce: nil)
        await s.answerAge(oldEnough: false)
        #expect(backend.deletedAccounts == 1)
        #expect(backend.sessionUserID == nil)
        #expect(!backend.ageConfirmed)
        #expect(gate.isBlocked)
        #expect(s.showAgeBlocked)
        #expect(s.phase == .signedOut)
        #expect(gate.pendingUserID == nil)
    }

    @Test("Cancel deletes the new account but does not block the phone")
    func cancelDeletes() async {
        let (s, backend, gate) = make { $0.startSignedOut(); $0.nextSignInCreatesAccount = true }
        await s.completeSignIn(idToken: "t", nonce: nil)
        await s.cancelAgeCheck()
        #expect(backend.deletedAccounts == 1)
        #expect(!gate.isBlocked)
        #expect(!s.ageCheckPending)
        #expect(s.phase == .signedOut)
    }

    @Test("A blocked phone cannot make a new account: it is deleted at once")
    func blockedPhoneRefusesSignUp() async {
        let (s, backend, _) = make({ $0.startSignedOut(); $0.nextSignInCreatesAccount = true }, blocked: true)
        await s.completeSignIn(idToken: "t", nonce: nil)
        #expect(backend.deletedAccounts == 1)
        #expect(!s.ageCheckPending)
        #expect(s.showAgeBlocked)
        #expect(s.phase == .signedOut)
    }

    @Test("A blocked phone can still sign in to an account that already exists")
    func blockedPhoneKeepsExistingAccounts() async {
        let (s, backend, _) = make({ $0.startSignedOut() }, blocked: true)
        await s.completeSignIn(idToken: "t", nonce: nil)
        #expect(s.phase == .signedIn)
        #expect(backend.deletedAccounts == 0)
    }

    @Test("Closing the app mid-question asks again on the next launch")
    func relaunchAsksAgain() {
        let (s, _, _) = make({ $0.startWithNewAccount() }, pending: DemoSocialBackend.me)
        #expect(s.ageCheckPending)
        #expect(s.phase == .signedOut)
    }

    @Test("A held account seen again later is still asked, however old it is")
    func heldAccountAskedEvenWhenOld() async {
        // signed out, but the phone still holds this account's id (its
        // deletion never reached the server); an ordinary sign-in follows
        let (s, _, _) = make({ $0.startSignedOut() }, pending: DemoSocialBackend.me)
        await s.completeSignIn(idToken: "t", nonce: nil)
        #expect(s.ageCheckPending)
        #expect(s.phase == .signedOut)
    }

    @Test("Existing signed-in accounts are never asked at launch")
    func existingSessionIsNotAsked() {
        let (s, _, _) = make()
        #expect(!s.ageCheckPending)
        #expect(s.phase == .signedIn)
    }
}
