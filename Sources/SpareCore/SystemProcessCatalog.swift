import Foundation

/// Well-known macOS processes. Generated from spareformac.com's process library (src/data/processes.json).
public enum SystemProcessCatalog {
    public struct Entry: Equatable {
        public let category: String
        public let summary: String
        public let slug: String

        public var learnMoreURL: URL? { URL(string: "https://spareformac.com/processes/\(slug)/") }
    }

    public static func entry(for name: String) -> Entry? { entries[name] }

    static let entries: [String: Entry] = [
        "airportd": .init(category: "Networking and devices", summary: "Manages your Mac’s Wi-Fi connection.", slug: "airportd"),
        "cloudd": .init(category: "iCloud and sync", summary: "Moves app data between your Mac and iCloud through CloudKit.", slug: "cloudd"),
        "coreaudiod": .init(category: "Audio", summary: "Runs all sound in and out of your Mac.", slug: "coreaudiod"),
        "corespotlightd": .init(category: "Spotlight and search", summary: "Indexes content inside apps, like notes and contacts, for search.", slug: "corespotlightd"),
        "distnoted": .init(category: "System core", summary: "Passes system-wide notifications between apps and services.", slug: "distnoted"),
        "fileproviderd": .init(category: "iCloud and sync", summary: "Connects iCloud Drive and cloud storage apps to Finder.", slug: "fileproviderd"),
        "kernel_task": .init(category: "System core", summary: "The macOS kernel, which also keeps your CPU from overheating.", slug: "kernel_task"),
        "launchd": .init(category: "System core", summary: "The first process macOS starts, which launches everything else.", slug: "launchd"),
        "logd": .init(category: "System core", summary: "Collects and stores the messages that macOS and apps log.", slug: "logd"),
        "mds_stores": .init(category: "Spotlight and search", summary: "Stores and updates Spotlight’s search index on each disk.", slug: "mds_stores"),
        "mdworker": .init(category: "Spotlight and search", summary: "Reads your files so Spotlight can search them.", slug: "mdworker"),
        "mdworker_shared": .init(category: "Spotlight and search", summary: "Reads your files so Spotlight can search them.", slug: "mdworker"),
        "mediaanalysisd": .init(category: "Photos and media", summary: "Analyzes photos and videos for search, Live Text, and Look Up.", slug: "mediaanalysisd"),
        "nsurlsessiond": .init(category: "Networking and devices", summary: "Finishes downloads and uploads that apps hand off to macOS.", slug: "nsurlsessiond"),
        "photoanalysisd": .init(category: "Photos and media", summary: "Scans your Photos library for people, places, and Memories.", slug: "photoanalysisd"),
        "rapportd": .init(category: "Networking and devices", summary: "Lets your Apple devices find and talk to each other nearby.", slug: "rapportd"),
        "remoted": .init(category: "Networking and devices", summary: "Finds connected Apple devices and the services they offer.", slug: "remoted"),
        "sharingd": .init(category: "Networking and devices", summary: "Powers AirDrop, Handoff, and Instant Hotspot.", slug: "sharingd"),
        "syspolicyd": .init(category: "Security and privacy", summary: "Checks that apps are allowed to run before macOS opens them.", slug: "syspolicyd"),
        "trustd": .init(category: "Security and privacy", summary: "Checks that certificates and secure connections can be trusted.", slug: "trustd"),
        "WindowServer": .init(category: "Display and graphics", summary: "Draws every window, menu, and pixel on your displays.", slug: "windowserver")
    ]
}
