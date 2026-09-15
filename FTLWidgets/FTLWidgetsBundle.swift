//
//  FTLWidgetsBundle.swift
//  FTLWidgets
//
//  Entry point for FTL Widget extensions.
//

import WidgetKit
import SwiftUI

@main
struct FTLWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DailyBudgetWidget()
        AddSpendWidget()
    }
}
