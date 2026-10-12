import Foundation

/// Docker Desktop's VM memory limit, from its settings-store.json, falling back to Docker's default of half the Mac's memory.
public enum DockerSettings {
    public static var settingsStore: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.docker/settings-store.json")
    }

    public struct MemoryLimit: Equatable {
        public let bytes: UInt64
        public let isDefault: Bool
    }

    public static func memoryLimit(physical: UInt64, from url: URL = settingsStore) -> MemoryLimit {
        parse((try? Data(contentsOf: url)) ?? Data(), physical: physical)
    }

    /// Docker has written the key as both `MemoryMiB` and `memoryMiB`, so it's matched without case.
    public static func parse(_ data: Data, physical: UInt64) -> MemoryLimit {
        if let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let mebibytes = settings.first(where: { $0.key.lowercased() == "memorymib" })?.value as? Int, mebibytes > 0 {
            return MemoryLimit(bytes: UInt64(mebibytes) * 1024 * 1024, isDefault: false)
        }
        return MemoryLimit(bytes: physical / 2, isDefault: true)
    }

    public static func isDocker(_ workload: Workload) -> Bool {
        workload.name.lowercased().contains("docker")
    }
}
