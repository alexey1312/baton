/// A `CodingKey` that accepts any string or integer key.
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// A structural view of a decoded TOML document that records key names at every
/// level while ignoring values.
///
/// Used to detect unrecognized keys for lenient forward-compatibility warnings
/// (see ``ConfigParser``), since `swift-toml`'s `TOMLValue` is not `Decodable`.
indirect enum TOMLKeyTree: Decodable {
    case table([String: TOMLKeyTree])
    case array([TOMLKeyTree])
    case leaf

    init(from decoder: any Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyCodingKey.self) {
            var dict: [String: TOMLKeyTree] = [:]
            for key in keyed.allKeys {
                dict[key.stringValue] = (try? keyed.decode(TOMLKeyTree.self, forKey: key)) ?? .leaf
            }
            self = .table(dict)
        } else if var unkeyed = try? decoder.unkeyedContainer() {
            var items: [TOMLKeyTree] = []
            while !unkeyed.isAtEnd {
                items.append((try? unkeyed.decode(TOMLKeyTree.self)) ?? .leaf)
            }
            self = .array(items)
        } else {
            self = .leaf
        }
    }
}
