import Foundation

enum Output {
    static var json = false

    static func print<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return }
        Swift.print(text)
    }

    /// Progress notes go to standard error so JSON on standard output stays clean.
    static func note(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        if json { print(["error": message]) } else { note(message) }
        exit(code)
    }
}
