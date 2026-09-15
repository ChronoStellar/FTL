//
//  HTMLNormalizer.swift
//  FTL — services/Pipeline/Normalization
//
//  Fast, deterministic HTML-to-text normalizer.
//  Strips scripts, styles, and tags while preserving layout structure
//  (table cells, row breaks, paragraphs) and decoding HTML entities.
//

import Foundation

nonisolated enum HTMLNormalizer: Sendable {

    /// Strips raw HTML into clean, layout-preserving plain text.
    static func strip(_ html: String) -> String? {
        guard !html.isEmpty else { return nil }

        var text = html

        // 1. Remove <style>...</style> blocks
        text = text.replacingOccurrences(
            of: #"(?is)<style\b[^>]*>.*?</style>"#,
            with: "",
            options: .regularExpression
        )

        // 2. Remove <script>...</script> blocks
        text = text.replacingOccurrences(
            of: #"(?is)<script\b[^>]*>.*?</script>"#,
            with: "",
            options: .regularExpression
        )

        // 3. Remove HTML comments <!-- ... -->
        text = text.replacingOccurrences(
            of: #"(?s)<!--.*?-->"#,
            with: "",
            options: .regularExpression
        )

        // 4. Convert cell boundaries to spacing
        text = text.replacingOccurrences(
            of: #"(?i)</t[dh]>"#,
            with: "  ",
            options: .regularExpression
        )

        // 5. Convert block-ending tags to newlines
        text = text.replacingOccurrences(
            of: #"(?i)<(?:/tr|/p|/div|/li|/h[1-6]|br\s*/?)>"#,
            with: "\n",
            options: .regularExpression
        )

        // 6. Strip all remaining HTML tags
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        // 7. Decode common HTML entities
        text = decodeEntities(text)

        // 8. Collapse repeated horizontal whitespace and blank lines
        text = cleanWhitespace(text)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeEntities(_ input: String) -> String {
        var str = input
        let entityMap: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&bull;", "•"),
            ("&middot;", "·"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&#x2F;", "/"),
            ("&#47;", "/"),
        ]
        for (entity, replacement) in entityMap {
            str = str.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        // Decimal numeric entities &#NNN;
        if str.contains("&#") {
            str = str.replacingOccurrences(of: #"&#(\d+);"#, with: { match in
                guard let scalarVal = UInt32(match),
                      let scalar = UnicodeScalar(scalarVal) else { return match }
                return String(Character(scalar))
            })
        }
        return str
    }

    private static func cleanWhitespace(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)

        var newlineCount = 0

        input.enumerateLines { line, _ in
            let trimmedLine = line
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty {
                if newlineCount < 2 {
                    result.append("\n")
                    newlineCount += 1
                }
            } else {
                if !result.isEmpty {
                    result.append("\n")
                }
                result.append(trimmedLine)
                newlineCount = 0
            }
        }

        return result
    }
}

private extension String {
    func replacingOccurrences(of pattern: String, with transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let nsString = self as NSString
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: nsString.length))
        var output = self
        for match in matches.reversed() {
            if match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                let matchedSub = nsString.substring(with: range)
                let replacement = transform(matchedSub)
                let fullRange = Range(match.range(at: 0), in: output)!
                output.replaceSubrange(fullRange, with: replacement)
            }
        }
        return output
    }
}
