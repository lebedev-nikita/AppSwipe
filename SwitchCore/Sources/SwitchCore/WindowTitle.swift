import Foundation

/// Separators between the parts of a window title.
private let separators = [" - ", " – ", " — "]

/// `title` without the app's name, which the Window Switcher already implies.
///
/// Apps such as Chrome end their titles with their name, as in "Page - Google Chrome – Profile". The
/// name is dropped only where it is a whole part after a separator, and never from a title that is
/// nothing else.
public func windowTitle(_ title: String, appName: String) -> String {
    guard !appName.isEmpty else { return title }
    for separator in separators {
        var searchEnd = title.endIndex
        while let range = title.range(of: separator + appName, options: .backwards, range: title.startIndex..<searchEnd) {
            let rest = title[range.upperBound...]
            if rest.isEmpty || separators.contains(where: rest.hasPrefix) {
                return title.replacingCharacters(in: range, with: "")
            }
            searchEnd = title.index(before: range.upperBound)
        }
    }
    return title
}
