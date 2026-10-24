import Foundation

struct OfflineSubtitleCue: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
}

enum OfflineSubtitleError: LocalizedError {
    case tooLarge, invalidEncoding, invalidTiming, tooManyCues, empty
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Choose a subtitle file smaller than 2 MB."
        case .invalidEncoding: return "Choose a UTF-8 SRT or VTT subtitle file."
        case .invalidTiming: return "The subtitle file contains an invalid timestamp."
        case .tooManyCues: return "The subtitle file contains too many cues."
        case .empty: return "No supported subtitles were found. Choose a UTF-8 SRT or VTT file."
        }
    }
}

enum OfflineSubtitleTrack {
    static func parse(data: Data) throws -> [OfflineSubtitleCue] {
        guard data.count <= 2_000_000 else { throw OfflineSubtitleError.tooLarge }
        guard var source = String(data: data, encoding: .utf8), !source.contains("\u{0000}") else { throw OfflineSubtitleError.invalidEncoding }
        if source.hasPrefix("\u{feff}") { source.removeFirst() }
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var index = 0, cues: [OfflineSubtitleCue] = []
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces); index += 1
            if line == "STYLE" || line == "REGION" || line == "NOTE" || line.hasPrefix("NOTE ") {
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
                continue
            }
            guard line.contains("-->") else { continue }
            let timing = line.components(separatedBy: "-->")
            guard timing.count == 2,
                  let endToken = timing[1].split(whereSeparator: { $0.isWhitespace }).first,
                  let start = timestamp(timing[0].trimmingCharacters(in: .whitespaces)),
                  let end = timestamp(String(endToken)) else { throw OfflineSubtitleError.invalidTiming }
            var body: [String] = []
            while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                body.append(lines[index]); index += 1
            }
            let text = plainText(body.joined(separator: "\n"))
            if end > start && !text.isEmpty {
                cues.append(OfflineSubtitleCue(start: start, end: end, text: text))
                guard cues.count <= 20_000 else { throw OfflineSubtitleError.tooManyCues }
            }
        }
        guard !cues.isEmpty else { throw OfflineSubtitleError.empty }
        return cues.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
    }

    static func text(at seconds: Double, cues: [OfflineSubtitleCue]) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "" }
        var low = 0, high = cues.count - 1, found = -1
        while low <= high {
            let middle = low + (high - low) / 2
            if cues[middle].start <= seconds { found = middle; low = middle + 1 }
            else { high = middle - 1 }
        }
        guard found >= 0, seconds < cues[found].end else { return "" }
        return cues[found].text
    }

    private static func timestamp(_ value: String) -> Double? {
        let parts = value.replacingOccurrences(of: ",", with: ".").split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        func digits(_ value: Substring, maximum: Int) -> Int? {
            guard !value.isEmpty, value.count <= maximum, value.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
            return Int(value)
        }
        let seconds = parts[parts.count - 1].split(separator: ".", omittingEmptySubsequences: false)
        guard seconds.count == 2, let wholeSeconds = digits(seconds[0], maximum: 2), wholeSeconds < 60,
              let fraction = digits(seconds[1], maximum: 3), let minutes = digits(parts[parts.count - 2], maximum: 2), minutes < 60 else { return nil }
        let hours: Int
        if parts.count == 3 {
            guard let value = digits(parts[0], maximum: 3) else { return nil }; hours = value
        } else { hours = 0 }
        return Double(hours * 3600 + minutes * 60 + wholeSeconds) + Double(fraction) / pow(10, Double(seconds[1].count))
    }

    private static func plainText(_ value: String) -> String {
        var text = value.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
