import Foundation

enum SharePayloadParser {
    static func url(from item: Any?) -> URL? {
        if let value = item as? URL { return value }
        if let value = item as? NSURL { return value as URL }
        if let value = item as? String { return URLExtractor.firstURL(in: value) }
        if let value = item as? NSString { return URLExtractor.firstURL(in: value as String) }
        if let value = item as? Data {
            return URLExtractor.firstURL(in: String(data: value, encoding: .utf8) ?? "")
        }
        return nil
    }
}
