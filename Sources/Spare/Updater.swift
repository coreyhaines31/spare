import Sparkle

/// Sparkle auto-updates, fed from the appcast attached to each GitHub release.
final class Updater {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
