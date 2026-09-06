//
//  SignInView.swift
//  FTL — view/Onboarding
//
//  The gate before anything else. The app is useless without a Google account:
//  the ledger is a Sheet and the primary capture rail is Gmail.
//
//  Says plainly what the access is for and where the data goes — "read your
//  email" is a large ask, and the honest answer (it stays on the device) is the
//  reason the whole architecture is shaped the way it is.
//

import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: GoogleAuthManager
    @State private var isWorking = false

    /// DEBUG only — see RootView.bypassAuth.
    var onDebugBypass: () -> Void = {}

    var body: some View {
        VStack(spacing: FTLSpacing.xl) {
            Spacer()

            VStack(spacing: FTLSpacing.md) {
                Text("FTL")
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .tracking(10)
                    .foregroundStyle(FTLColor.textPrimary)
                Text("Your ledger, kept current without the data entry.")
                    .font(FTLTypography.bodyRegular)
                    .foregroundStyle(FTLColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            GlassCard(cornerRadius: FTLRadius.card, padding: FTLSpacing.lg, isElevated: false) {
                VStack(alignment: .leading, spacing: FTLSpacing.md) {
                    capability(
                        icon: "envelope",
                        title: "Reads receipt emails",
                        detail: "Read-only. Parsing happens on this device."
                    )
                    capability(
                        icon: "tablecells",
                        title: "Writes to your Sheet",
                        detail: "Only rows you approve. It stays your spreadsheet."
                    )
                }
            }

            Spacer()

            Button {
                Task {
                    isWorking = true
                    await auth.signIn()
                    isWorking = false
                }
            } label: {
                HStack(spacing: FTLSpacing.sm) {
                    if isWorking { ProgressView().tint(FTLColor.onLight) }
                    Text("Continue with Google")
                }
                .font(FTLTypography.rowTitle)
                .foregroundStyle(FTLColor.onLight)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(FTLColor.textPrimary, in: RoundedRectangle(cornerRadius: FTLRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            if let error = auth.errorMessage {
                Text(error)
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(FTLColor.error)
                    .multilineTextAlignment(.center)
            }

            #if DEBUG
            Button("Skip sign-in (debug)", action: onDebugBypass)
                .font(FTLTypography.captionSmall)
                .tint(FTLColor.textDisabled)
            #endif
        }
        .padding(FTLSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlowBackground())
    }

    private func capability(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: FTLSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(FTLColor.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: FTLSpacing.xxs) {
                Text(title)
                    .font(FTLTypography.body)
                    .foregroundStyle(FTLColor.textPrimary)
                Text(detail)
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(FTLColor.textSecondary)
            }
        }
    }
}
