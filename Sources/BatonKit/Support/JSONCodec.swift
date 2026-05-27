import Foundation
import YYJSON

/// DOM value for untyped JSON access via subscripts.
public typealias JSONValue = YYJSONValue

/// DOM object for key-value iteration.
public typealias JSONObject = YYJSONObject

/// DOM array for indexed/sequential access.
public typealias JSONArray = YYJSONArray

/// Centralized JSON codec based on YYJSON (ported from ExFig).
///
/// A high-performance replacement for Foundation JSON on all platforms. Baton uses
/// the DOM API (``parseValue(from:)``) for robustly parsing agent responses whose
/// shape varies between CLIs, and the Codable helpers for run records and renders.
public enum JSONCodec {
    // MARK: - DOM Parsing

    /// Parse JSON data into a DOM value for untyped access.
    ///
    /// Use when the JSON structure is too dynamic for Codable. Access values via
    /// subscripts: `value["key"]?.string`, `.number`, `.array`.
    public static func parseValue(from data: Data) throws -> JSONValue {
        try JSONValue(data: data)
    }

    /// Parse a JSON string into a DOM value.
    public static func parseValue(from string: String) throws -> JSONValue {
        try parseValue(from: Data(string.utf8))
    }

    // MARK: - Encoding

    /// Encode a value to JSON data.
    public static func encode(_ value: some Encodable) throws -> Data {
        try YYJSONEncoder().encode(value)
    }

    /// Encode a value to pretty-printed JSON data.
    public static func encodePretty(_ value: some Encodable) throws -> Data {
        var encoder = YYJSONEncoder()
        encoder.writeOptions = [.prettyPrinted]
        return try encoder.encode(value)
    }

    /// Encode with sorted keys for deterministic output (e.g. hashing).
    public static func encodeSorted(_ value: some Encodable) throws -> Data {
        var encoder = YYJSONEncoder()
        encoder.writeOptions = [.sortedKeys]
        return try encoder.encode(value)
    }

    /// Encode with pretty-print and sorted keys for human-readable, stable files.
    public static func encodePrettySorted(_ value: some Encodable) throws -> Data {
        var encoder = YYJSONEncoder()
        encoder.writeOptions = [.indentationTwoSpaces, .sortedKeys]
        return try encoder.encode(value)
    }

    /// Encode with ISO8601 date encoding and pretty-print (e.g. run manifests).
    public static func encodeWithISO8601DatePretty(_ value: some Encodable) throws -> Data {
        var encoder = YYJSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.writeOptions = [.prettyPrinted]
        return try encoder.encode(value)
    }

    // MARK: - Decoding

    /// Decode JSON data into a type.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try YYJSONDecoder().decode(type, from: data)
    }

    /// Decode JSON data with the ISO8601 date strategy.
    public static func decodeWithISO8601Date<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var decoder = YYJSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
