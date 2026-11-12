import Foundation

/// One folder of debug symbols Xcode copied from a device, like
/// ~/Library/Developer/Xcode/iOS DeviceSupport/iPhone12,8 27.2 (24B119).
/// Xcode makes one per device model and exact build, and copies it again
/// (several minutes) when a device with that build is connected.
public struct DeviceSupportVersion: Identifiable, Hashable, Sendable {
    public var path: String
    /// iOS, watchOS, tvOS, visionOS, or macOS, from the parent folder.
    public var platform: String
    /// The model identifier, like iPhone12,8. Older Xcode versions left it out.
    public var device: String?
    public var version: String
    public var build: String
    public var bytes: Int64
    public var modified: Date

    public init(path: String, platform: String, device: String?, version: String, build: String, bytes: Int64, modified: Date) {
        self.path = path
        self.platform = platform
        self.device = device
        self.version = version
        self.build = build
        self.bytes = bytes
        self.modified = modified
    }

    public var id: String { path }

    /// Versions of the same device, compared with each other: iOS · iPhone12,8.
    public var group: String { [platform, device].compactMap { $0 }.joined(separator: " · ") }

    /// 27.2 (24B119)
    public var title: String { "\(version) (\(build))" }

    /// True when this one is newer: by version number, then by build, so 27.10 beats 27.9 and 24C55 beats 24B119.
    public func isNewer(than other: DeviceSupportVersion) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = other.version.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return build.compare(other.build, options: .numeric) == .orderedDescending
    }
}

public enum DeviceSupportFinder {
    /// The DeviceSupport folders Xcode keeps, one per platform.
    public static let folders = ["~/Library/Developer/Xcode/iOS DeviceSupport",
                                 "~/Library/Developer/Xcode/watchOS DeviceSupport",
                                 "~/Library/Developer/Xcode/tvOS DeviceSupport",
                                 "~/Library/Developer/Xcode/visionOS DeviceSupport",
                                 "~/Library/Developer/Xcode/macOS DeviceSupport"]

    /// iOS DeviceSupport -> iOS.
    public static func platform(ofFolder folder: String) -> String {
        (folder as NSString).lastPathComponent.replacingOccurrences(of: " DeviceSupport", with: "")
    }

    /// Reads "iPhone12,8 27.2 (24B119)", "17.0 (21A329)", or "17.0 (21A329) arm64e".
    /// Nil for a name that is not a version, which is then never touched.
    public static func parse(_ name: String) -> (device: String?, version: String, build: String)? {
        guard let open = name.firstIndex(of: "("), let close = name[open...].firstIndex(of: ")") else { return nil }
        let build = String(name[name.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        let words = name[..<open].split(separator: " ")
        guard !build.isEmpty, let last = words.last, words.count <= 2 else { return nil }
        let version = String(last)
        guard version.split(separator: ".").allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return (words.count == 2 ? String(words[0]) : nil, version, build)
    }

    /// The newest version of each device: kept unless the person picks it.
    public static func newest(_ versions: [DeviceSupportVersion]) -> Set<String> {
        var best: [String: DeviceSupportVersion] = [:]
        for version in versions {
            if let current = best[version.group], !version.isNewer(than: current) { continue }
            best[version.group] = version
        }
        return Set(best.values.map(\.path))
    }

    /// Groups in a steady order, each newest first.
    public static func grouped(_ versions: [DeviceSupportVersion]) -> [(group: String, versions: [DeviceSupportVersion])] {
        Dictionary(grouping: versions, by: \.group)
            .map { ($0.key, $0.value.sorted { $0.isNewer(than: $1) }) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    /// What the Storage row shows: the older versions, and how many newest ones stay.
    public static func size(of versions: [DeviceSupportVersion]) -> CleanupSize {
        let keep = newest(versions)
        let old = versions.filter { !keep.contains($0.path) }
        return CleanupSize(bytes: old.reduce(0) { $0 + $1.bytes }, items: old.count, kept: keep.count)
    }
}
