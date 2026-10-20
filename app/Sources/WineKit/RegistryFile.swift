import Foundation

/// Read-only view of Wine's text registry files (user.reg / system.reg). Only string values are decoded.
/// Writes go through `wine reg`, which is safe while a wineserver is running; editing the file is not.
public struct RegistryFile: Sendable {
    /// Key path (unescaped, lowercased, e.g. `software\wine\dlloverrides`) → value name (lowercased) → value.
    private var keys: [String: [String: (name: String, value: String)]] = [:]

    public init(contentsOf url: URL) {
        self.init(text: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    public init(text: String) {
        var current: String?
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = Substring(raw)
            if line.hasPrefix("[") {
                guard let close = Self.closingBracket(line) else { current = nil; continue }
                current = Self.unescape(line[line.index(after: line.startIndex)..<close]).lowercased()
                continue
            }
            guard let key = current, line.hasPrefix("\""),
                  let (name, rest) = Self.quoted(line[line.index(after: line.startIndex)...]),
                  rest.hasPrefix("=\"") else { continue }
            guard let (value, _) = Self.quoted(rest.dropFirst(2)) else { continue }
            keys[key, default: [:]][name.lowercased()] = (name, value)
        }
    }

    /// String values of `key` (backslash-separated, case-insensitive), keyed by value name as written.
    public func values(of key: String) -> [String: String] {
        var out: [String: String] = [:]
        for (_, v) in keys[key.lowercased()] ?? [:] { out[v.name] = v.value }
        return out
    }

    public func value(_ name: String, in key: String) -> String? {
        keys[key.lowercased()]?[name.lowercased()]?.value
    }

    private static func closingBracket(_ line: Substring) -> Substring.Index? {
        var escaped = false
        for i in line.indices.dropFirst() {
            let c = line[i]
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "]" { return i }
        }
        return nil
    }

    /// Reads up to the closing quote (handling `\"` and `\\`); returns the decoded text and what follows it.
    private static func quoted(_ s: Substring) -> (String, Substring)? {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\"" { return (out, s[s.index(after: i)...]) }
            if c == "\\" {
                let n = s.index(after: i)
                guard n < s.endIndex else { return nil }
                switch s[n] {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "0": out.append("\0")
                case "x":
                    // \xHHHH: up to four hex digits, a UTF-16 code unit.
                    var j = s.index(after: n)
                    var hex = ""
                    while j < s.endIndex, hex.count < 4, s[j].isHexDigit { hex.append(s[j]); j = s.index(after: j) }
                    if let u = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(u) { out.unicodeScalars.append(scalar) }
                    i = j
                    continue
                default: out.append(s[n])
                }
                i = s.index(after: n)
                continue
            }
            out.append(c)
            i = s.index(after: i)
        }
        return nil
    }

    private static func unescape(_ s: Substring) -> String {
        var out = ""
        var escaped = false
        for c in s {
            if escaped { out.append(c); escaped = false } else if c == "\\" { escaped = true } else { out.append(c) }
        }
        return out
    }
}
