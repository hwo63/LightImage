import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case vietnamese = "vi"
    case english = "en"

    public static let defaultsKey = "language"
    public static var current: Self {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .vietnamese
    }
    public var locale: Locale { Locale(identifier: rawValue) }
}

/// Keeps interpolated values separate from the template so names, paths and
/// other user data are never passed to the localization lookup.
public struct InterfaceText: ExpressibleByStringInterpolation, Sendable {
    public struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var key = ""
        fileprivate var values: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + 2 * interpolationCount)
            values.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) { key += literal }

        public mutating func appendInterpolation<T>(_ value: T) {
            key += "%@"
            values.append(String(describing: value))
        }
    }

    private let key: String
    private let values: [String]
    private static let english: Bundle? = {
        let embedded = Bundle.main.url(forResource: "LightImage_LightImageCore", withExtension: "bundle")
            .flatMap(Bundle.init(url:))
        return (embedded ?? Bundle.module).url(forResource: "en", withExtension: "lproj").flatMap(Bundle.init(url:))
    }()

    public init(stringLiteral value: String) {
        key = value
        values = []
    }

    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        values = stringInterpolation.values
    }

    public func localized(_ language: AppLanguage = .current) -> String {
        let template = language == .english ? Self.english?.localizedString(forKey: key, value: key, table: nil) ?? key : key
        guard !values.isEmpty else { return template }
        var parts = template.components(separatedBy: "%@")
        if parts.count != values.count + 1 { parts = key.components(separatedBy: "%@") }
        guard parts.count == values.count + 1 else { return key }
        return parts[0] + zip(values, parts.dropFirst()).map { $0 + $1 }.joined()
    }
}

public func tr(_ message: InterfaceText) -> String { message.localized() }
