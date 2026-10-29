import Foundation

/// Turns RSS-style HTML descriptions into plain text without WebKit.
///
/// `NSAttributedString`'s HTML importer runs WebKit on the main thread, which stalls lists.
/// Feed descriptions only need tags removed, paragraphs kept, and common entities decoded.
enum PlainText {
    static func from(html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"<\s*br\s*/?\s*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"</\s*(p|div|li|h[1-6])\s*>"#, with: "\n\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&rsquo;": "\u{2019}",
            "&lsquo;": "\u{2018}", "&rdquo;": "\u{201D}", "&ldquo;": "\u{201C}",
            "&hellip;": "\u{2026}", "&mdash;": "\u{2014}", "&ndash;": "\u{2013}"
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }

        text = text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n\s*\n\s*(\n\s*)+"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
