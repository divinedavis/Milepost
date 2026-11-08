import SwiftUI

/// What RootView covers the app with while a new account waits for its age
/// answer, and the friendly screen an under-13 answer gets. See AgeGate.swift.
struct AgeGateCover: View {
    @Environment(SocialStore.self) private var social

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if social.ageCheckPending {
                AgeGateForm(
                    working: social.ageAnswerInFlight,
                    error: social.lastError,
                    onAnswer: { oldEnough in Task { await social.answerAge(oldEnough: oldEnough) } },
                    onCancel: { Task { await social.cancelAgeCheck() } }
                )
            } else {
                AgeBlockedView { social.showAgeBlocked = false }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }
}

/// Birth month + year with nothing pre-selected. The copy never says what
/// age is required, and the answer is used only on the phone.
struct AgeGateForm: View {
    var working = false
    var error: String?
    /// Called with `true` for 13+, `false` for under 13.
    let onAnswer: (Bool) -> Void
    let onCancel: () -> Void

    @State private var month: Int?
    @State private var year: Int?

    private let years = AgeGate.selectableYears()
    private var monthNames: [String] { Calendar.current.monthSymbols }
    private var answered: Bool { month != nil && year != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("Cancel", action: onCancel)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minHeight: 44)
                    .disabled(working)
                    .accessibilityIdentifier("ageGate.cancel")
                    .padding(.bottom, 16)

                Text("When were you born?")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("ageGate.title")

                Text("Enter your birth month and year to set up your Milepost account. Your answer stays on this phone.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)

                HStack(spacing: 0) {
                    Picker("Birth month", selection: $month) {
                        Text("Month").tag(Int?.none)
                        ForEach(Array(monthNames.enumerated()), id: \.offset) { idx, name in
                            Text(name).tag(Int?.some(idx + 1))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityIdentifier("ageGate.month")

                    Picker("Birth year", selection: $year) {
                        Text("Year").tag(Int?.none)
                        ForEach(years, id: \.self) { y in
                            Text(String(y)).tag(Int?.some(y))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityIdentifier("ageGate.year")
                }
                .frame(height: 180)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, 20)

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)
                        .accessibilityIdentifier("ageGate.error")
                }

                Button {
                    guard let month, let year else { return }
                    onAnswer(AgeGate.isOldEnough(birthYear: year, birthMonth: month))
                } label: {
                    Text(working ? "Setting up…" : "Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Theme.accent))
                }
                .disabled(!answered || working)
                .opacity(answered ? 1 : 0.4)
                .accessibilityIdentifier("ageGate.continue")
            }
            .padding(24)
        }
    }
}

/// Shown once the answer is under 13. No account was made; nothing about
/// the answer was sent anywhere.
struct AgeBlockedView: View {
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "figure.run")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accentText)
                    .accessibilityHidden(true)
                Text("Thanks for your interest in Milepost friends!")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("ageBlocked.title")
                Text("You're not able to create an account right now. You can still record your runs, walks and rides on this phone. We'd love to see you back when you're older.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // The 44 pt frame goes on the label: outside the Link it grows
                // the layout but not the tap target (the audit's hit region).
                Link(destination: LegalLinks.privacy) {
                    Text("Privacy Policy")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("ageBlocked.privacy")
                Button(action: onDone) {
                    Text("OK")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Theme.accent))
                }
                .accessibilityIdentifier("ageBlocked.done")
            }
            .padding(24)
            .padding(.top, 40)
        }
    }
}

/// Under the sign-in button on a phone that answered under 13: a new account
/// cannot be made here, but an existing one (a parent's) can still sign in.
struct AgeBlockedNote: View {
    var body: some View {
        Text("New accounts can't be created on this phone. You can still sign in to an account that already exists.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("ageBlocked.note")
    }
}

/// The legal pages the app links to, in one place.
enum LegalLinks {
    static let privacy = URL(string: "https://divinedavis.com/milepost/privacy/")!
    static let support = URL(string: "https://divinedavis.com/milepost/support/")!
}
