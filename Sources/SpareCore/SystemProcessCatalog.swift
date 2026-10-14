import Foundation

/// Well-known macOS processes. Generated from spareformac.com's process library (src/data/processes.json).
public enum SystemProcessCatalog {
    public struct Entry: Equatable {
        public let category: String
        public let summary: String
    }

    /// Matches by name only for executables macOS ships, so a look-alike elsewhere stays unidentified.
    public static func entry(for process: ProcessRecord) -> Entry? {
        isShipped(process.path) || process.identity.pid == 0 ? entries[process.name] : nil
    }

    /// Locations only macOS installs to. `/Library/Apple/System` holds XProtect, which updates separately.
    public static func isShipped(_ path: String) -> Bool {
        ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/", "/Library/Apple/System/"].contains(where: path.hasPrefix)
    }

    static let entries: [String: Entry] = [
        "accountsd": .init(category: "iCloud and sync", summary: "Stores the internet accounts that Mail, Calendar, and Contacts use."),
        "airportd": .init(category: "Networking and devices", summary: "Manages your Mac’s Wi-Fi connection."),
        "AMPDevicesAgent": .init(category: "Networking and devices", summary: "Manages iPhones and iPads connected to your Mac for syncing and backups."),
        "apsd": .init(category: "Networking and devices", summary: "Keeps your Mac connected to Apple’s push notification service."),
        "callservicesd": .init(category: "Messages and calls", summary: "Keeps track of FaceTime and phone calls on your Mac."),
        "cfprefsd": .init(category: "System core", summary: "Reads and saves every app’s settings."),
        "cloudd": .init(category: "iCloud and sync", summary: "Moves app data between your Mac and iCloud through CloudKit."),
        "contactsd": .init(category: "iCloud and sync", summary: "Manages your contacts database and keeps it in sync."),
        "coreaudiod": .init(category: "Audio", summary: "Runs all sound in and out of your Mac."),
        "coreduetd": .init(category: "Siri and suggestions", summary: "Tracks device activity that macOS uses to schedule work and suggestions."),
        "corespotlightd": .init(category: "Spotlight and search", summary: "Indexes content inside apps, like notes and contacts, for search."),
        "distnoted": .init(category: "System core", summary: "Passes system-wide notifications between apps and services."),
        "duetexpertd": .init(category: "Siri and suggestions", summary: "Learns how you use your Mac to power Siri Suggestions."),
        "fileproviderd": .init(category: "iCloud and sync", summary: "Connects iCloud Drive and cloud storage apps to Finder."),
        "fseventsd": .init(category: "System core", summary: "Records every file change so Spotlight, Time Machine, and apps can react."),
        "hidd": .init(category: "System core", summary: "Processes input from your keyboard, mouse, and trackpad."),
        "identityservicesd": .init(category: "Messages and calls", summary: "Registers your Mac with iMessage, FaceTime, and Continuity."),
        "imagent": .init(category: "Messages and calls", summary: "Keeps Messages connected so texts arrive even when the app is closed."),
        "kernel_task": .init(category: "System core", summary: "The macOS kernel, which also keeps your CPU from overheating."),
        "launchd": .init(category: "System core", summary: "The first process macOS starts, which launches everything else."),
        "logd": .init(category: "System core", summary: "Collects and stores the messages that macOS and apps log."),
        "loginwindow": .init(category: "System core", summary: "Runs your login session, the lock screen, and the Force Quit window."),
        "mDNSResponder": .init(category: "Networking and devices", summary: "Looks up every website address and finds devices on your network."),
        "mds_stores": .init(category: "Spotlight and search", summary: "Stores and updates Spotlight’s search index on each disk."),
        "mdworker": .init(category: "Spotlight and search", summary: "Reads your files so Spotlight can search them."),
        "mdworker_shared": .init(category: "Spotlight and search", summary: "Reads your files so Spotlight can search them."),
        "mediaanalysisd": .init(category: "Photos and media", summary: "Analyzes photos and videos for search, Live Text, and Look Up."),
        "mobileassetd": .init(category: "System core", summary: "Downloads the extra pieces of macOS that arrive on demand."),
        "nsurlsessiond": .init(category: "Networking and devices", summary: "Finishes downloads and uploads that apps hand off to macOS."),
        "photoanalysisd": .init(category: "Photos and media", summary: "Scans your Photos library for people, places, and Memories."),
        "photolibraryd": .init(category: "Photos and media", summary: "Handles every request to your Photos library."),
        "powerd": .init(category: "System core", summary: "Manages sleep, wake, and what’s keeping your Mac awake."),
        "rapportd": .init(category: "Networking and devices", summary: "Lets your Apple devices find and talk to each other nearby."),
        "remoted": .init(category: "Networking and devices", summary: "Finds connected Apple devices and the services they offer."),
        "replayd": .init(category: "Display and graphics", summary: "Records and broadcasts app screens through ReplayKit."),
        "searchpartyd": .init(category: "Networking and devices", summary: "Runs the Find My network that locates your devices and AirTags."),
        "sharingd": .init(category: "Networking and devices", summary: "Powers AirDrop, Handoff, and Instant Hotspot."),
        "spindump": .init(category: "System core", summary: "Records what a frozen app was doing when it stopped responding."),
        "suggestd": .init(category: "Siri and suggestions", summary: "Finds events, contacts, and other details in your apps to suggest them."),
        "sysmond": .init(category: "System core", summary: "Collects the process statistics Activity Monitor shows you."),
        "syspolicyd": .init(category: "Security and privacy", summary: "Checks that apps are allowed to run before macOS opens them."),
        "trustd": .init(category: "Security and privacy", summary: "Checks that certificates and secure connections can be trusted."),
        "VTDecoderXPCService": .init(category: "Photos and media", summary: "Decodes video for apps, using your Mac’s media hardware when it can."),
        "WindowServer": .init(category: "Display and graphics", summary: "Draws every window, menu, and pixel on your displays."),
        "XProtect": .init(category: "Security and privacy", summary: "Apple’s built-in malware scanner, updated separately from macOS."),
        "xprotectd": .init(category: "Security and privacy", summary: "Apple’s built-in malware scanner, updated separately from macOS.")
    ]
}
