import Foundation

enum ExposureFormat {
    static func shutterSeconds(from value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? Double { return sanitizeShutter(number) }
        if let number = value as? NSNumber { return sanitizeShutter(number.doubleValue) }
        if let text = value as? String { return parseShutterString(text) }
        return nil
    }

    static func apertureValue(from value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? Double { return sanitizeAperture(number) }
        if let number = value as? NSNumber { return sanitizeAperture(number.doubleValue) }
        if let text = value as? String { return parseApertureString(text) }
        return nil
    }

    static func parseShutterString(_ raw: String) -> Double? {
        let text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "seconds", with: "")
            .replacingOccurrences(of: "second", with: "")
            .replacingOccurrences(of: "sec", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let slash = text.firstIndex(of: "/") {
            let numerator = Double(text[..<slash].trimmingCharacters(in: .whitespaces))
            let denominatorText = text[text.index(after: slash)...]
                .replacingOccurrences(of: "s", with: "")
                .trimmingCharacters(in: .whitespaces)
            let denominator = Double(denominatorText)
            if let numerator, let denominator, denominator != 0 {
                return sanitizeShutter(numerator / denominator)
            }
            return nil
        }

        let stripped = text.hasSuffix("s") ? String(text.dropLast()) : text
        if let value = Double(stripped.trimmingCharacters(in: .whitespaces)) {
            return sanitizeShutter(value)
        }
        return nil
    }

    static func parseApertureString(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("f/") { text = String(text.dropFirst(2)) }
        else if text.hasPrefix("f") { text = String(text.dropFirst()) }
        text = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(text) else { return nil }
        return sanitizeAperture(value)
    }

    static func shutterLabel(_ seconds: Double) -> String {
        if seconds >= 0.3 {
            if abs(seconds - seconds.rounded()) < 0.05 {
                return "\(Int(seconds.rounded()))s"
            }
            return String(format: "%.1fs", seconds)
        }

        let denominator = (1.0 / seconds).rounded()
        if denominator >= 1 {
            return "1/\(Int(denominator))"
        }
        return String(format: "%.3fs", seconds)
    }

    static func apertureLabel(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 {
            return "f/\(Int(value.rounded()))"
        }
        return String(format: "f/%.1f", value)
    }

    static func isoLabel(_ value: Double) -> String {
        "ISO \(Int(value.rounded()))"
    }

    static func focalLabel(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.2 {
            return "\(Int(value.rounded()))mm"
        }
        return String(format: "%.1fmm", value)
    }

    static func logInterpolate(t: Double, range: ClosedRange<Double>) -> Double {
        let lower = max(range.lowerBound, 1e-6)
        let upper = max(range.upperBound, lower)
        let logMin = log(lower)
        let logMax = log(upper)
        return exp(logMin + min(max(t, 0), 1) * (logMax - logMin))
    }

    static func logPosition(_ value: Double, range: ClosedRange<Double>) -> Double {
        let lower = max(range.lowerBound, 1e-6)
        let upper = max(range.upperBound, lower)
        let logMin = log(lower)
        let logMax = log(upper)
        guard logMax > logMin else { return 0 }
        return min(max((log(max(value, 1e-6)) - logMin) / (logMax - logMin), 0), 1)
    }

    private static func sanitizeShutter(_ value: Double) -> Double? {
        guard value.isFinite, value > 0, value <= 3600 else { return nil }
        return value
    }

    private static func sanitizeAperture(_ value: Double) -> Double? {
        guard value.isFinite, value > 0.5, value < 128 else { return nil }
        return value
    }
}
