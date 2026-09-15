//
//  LoadPhase.swift
//  FTL — viewModel
//
//  One screen-state enum for every view model. A view model never rethrows to a
//  view: it catches, and publishes `.failed` with something a human can read.
//

import Foundation

@MainActor
enum LoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool { self == .loading }

    var errorMessage: String? {
        if case let .failed(message) = self { return message }
        return nil
    }
}
