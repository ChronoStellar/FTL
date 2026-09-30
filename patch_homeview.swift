import Foundation

let file = "FTL/view/Home/HomeView.swift"
var content = try String(contentsOfFile: file)

let search = """
    private var bucketRows: [BudgetPosition] {
        guard let root = viewModel.buckets.first else { return [] }
        return root.children.filter { $0.id != .unallocated || $0.actual.minorUnits > 0 }
    }
"""
let replace = """
    private var bucketRows: [BudgetPosition] {
        guard let root = viewModel.buckets.first else { return [] }
        return root.children.filter { bucket in
            if bucket.id == .unallocated && bucket.actual.minorUnits == 0 { return false }
            if bucket.id == .emergency && bucket.actual.minorUnits == 0 { return false }
            return true
        }
    }
"""
content = content.replacingOccurrences(of: search, with: replace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
