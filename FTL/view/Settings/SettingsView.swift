//
//  SettingsView.swift
//  FTL — view/Settings · Phase 1
//
//  Reached from the FTL wordmark. The design has no other home for it, and Sign
//  out has to be reachable.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: GoogleAuthManager
    let trustLevel: TrustLevel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Account")
                        .padding(.bottom, FTLSpacing.labelGap)
                    accountPanel

                    SectionLabel(text: "Trust")
                        .padding(.top, FTLSpacing.xl)
                        .padding(.bottom, FTLSpacing.labelGap)
                    trustPanel

                    #if DEBUG
                    SectionLabel(text: "Developer")
                        .padding(.top, FTLSpacing.xl)
                        .padding(.bottom, FTLSpacing.labelGap)
                    debugPanel
                    #endif
                }
                .padding(.horizontal, FTLSpacing.screenMargin)
                .padding(.bottom, FTLSpacing.xxl)
            }
            .scrollContentBackground(.hidden)
            .background(FTLColor.sheetBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FTLColor.sheetBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone).tint(FTLColor.textTertiary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(FTLColor.ground)
        .presentationCornerRadius(FTLRadius.sheet)
    }

    private var accountPanel: some View {
        PanelCard {
            valueRow("Name", auth.name ?? "—")
            valueRow("Email", auth.email ?? "—")
            PanelRow(showsDivider: false) {
                Button("Sign out", role: .destructive) {
                    auth.signOut()
                    onDone()
                }
                .font(FTLTypography.rowTitle)
                .tint(FTLColor.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var trustPanel: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
            PanelCard {
                valueRow("Mode", trustLevel.rawValue.capitalized, showsDivider: false)
            }
            // Not a placeholder. Auto is withheld on evidence, and the number is
            // here so the reason survives contact with someone who wants it on.
            Text("Every captured row waits for your approval. Auto-approval stays off until accuracy is re-measured — the last run put unattended writes at 67% correct.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
        }
    }

    #if DEBUG
    private var debugPanel: some View {
        PanelCard {
            NavigationLink {
                DebugView()
            } label: {
                PanelRow(showsDivider: false) {
                    HStack {
                        Text("Google API harness")
                            .font(FTLTypography.rowTitle)
                            .foregroundStyle(FTLColor.textPrimary)
                        Spacer()
                        Chevron()
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
    #endif

    private func valueRow(_ label: String, _ value: String, showsDivider: Bool = true) -> some View {
        PanelRow(showsDivider: showsDivider) {
            HStack {
                Text(label)
                    .font(FTLTypography.rowTitle)
                    .foregroundStyle(FTLColor.textPrimary)
                Spacer(minLength: FTLSpacing.sm)
                Text(value)
                    .font(FTLTypography.bodyRegular)
                    .foregroundStyle(FTLColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}
