import Foundation

/// Well-known macOS processes. Generated from spareformac.com's process library (src/data/processes.json).
public enum SystemProcessCatalog {
    public struct Entry: Equatable {
        public let category: String
        public let summary: String
    }

    /// Matches by name only for executables macOS ships, so a look-alike elsewhere stays unidentified.
    public static func entry(for process: ProcessRecord) -> Entry? {
        let shipped = ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/"].contains(where: process.path.hasPrefix) || process.identity.pid == 0
        return shipped ? entries[process.name] : nil
    }

    static let entries: [String: Entry] = [
        "airportd": .init(category: "Networking and devices", summary: "Manages your Mac’s Wi-Fi connection."),
        "cloudd": .init(category: "iCloud and sync", summary: "Moves app data between your Mac and iCloud through CloudKit."),
        "coreaudiod": .init(category: "Audio", summary: "Runs all sound in and out of your Mac."),
        "corespotlightd": .init(category: "Spotlight and search", summary: "Indexes content inside apps, like notes and contacts, for search."),
        "distnoted": .init(category: "System core", summary: "Passes system-wide notifications between apps and services."),
        "fileproviderd": .init(category: "iCloud and sync", summary: "Connects iCloud Drive and cloud storage apps to Finder."),
        "kernel_task": .init(category: "System core", summary: "The macOS kernel, which also keeps your CPU from overheating."),
        "launchd": .init(category: "System core", summary: "The first process macOS starts, which launches everything else."),
        "logd": .init(category: "System core", summary: "Collects and stores the messages that macOS and apps log."),
        "mds_stores": .init(category: "Spotlight and search", summary: "Stores and updates Spotlight’s search index on each disk."),
        "mdworker": .init(category: "Spotlight and search", summary: "Reads your files so Spotlight can search them."),
        "mdworker_shared": .init(category: "Spotlight and search", summary: "Reads your files so Spotlight can search them."),
        "mediaanalysisd": .init(category: "Photos and media", summary: "Analyzes photos and videos for search, Live Text, and Look Up."),
        "nsurlsessiond": .init(category: "Networking and devices", summary: "Finishes downloads and uploads that apps hand off to macOS."),
        "photoanalysisd": .init(category: "Photos and media", summary: "Scans your Photos library for people, places, and Memories."),
        "rapportd": .init(category: "Networking and devices", summary: "Lets your Apple devices find and talk to each other nearby."),
        "remoted": .init(category: "Networking and devices", summary: "Finds connected Apple devices and the services they offer."),
        "sharingd": .init(category: "Networking and devices", summary: "Powers AirDrop, Handoff, and Instant Hotspot."),
        "syspolicyd": .init(category: "Security and privacy", summary: "Checks that apps are allowed to run before macOS opens them."),
        "trustd": .init(category: "Security and privacy", summary: "Checks that certificates and secure connections can be trusted."),
        "WindowServer": .init(category: "Display and graphics", summary: "Draws every window, menu, and pixel on your displays.")
    ]
}
