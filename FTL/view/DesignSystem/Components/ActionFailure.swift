//
//  ActionFailure.swift
//  FTL — view/DesignSystem/Components
//
//  Telling a person that something they did did not work.
//
//  This exists because three screens were not. `ApprovalQueueViewModel` wrote
//  `phase = .failed` in ten places, `ApprovalQueueSheet` read `phase` in none,
//  and `BucketDetailView` and `GoalDetailView` read it in none either — so an
//  approval that never reached the Sheet, a correction that never saved and a
//  ceiling that never moved all looked exactly like success. On the one screen
//  that is the sole path into the canonical ledger, that is the worst available
//  failure mode: the row goes on showing the old figure and there is nothing to
//  tell you it is still the old figure.
//
//  A LOAD failure and an ACTION failure are different things and this app was
//  putting both in the same place. A screen that cannot load has nothing to show
//  and says so inline, where the content would be. A screen that loaded fine and
//  then failed to save still has all its content, and needs to interrupt —
//  so: a native alert, which is unmissable and which nobody has to notice.
//

import SwiftUI

extension View {
    /// Presents `message` as an alert and clears it on dismissal.
    ///
    /// Bound rather than passed so dismissal clears the view model's own state;
    /// otherwise the alert returns the next time anything redraws.
    func actionFailureAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Couldn't save",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }
}
