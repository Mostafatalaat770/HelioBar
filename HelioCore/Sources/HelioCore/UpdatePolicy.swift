import Foundation

/// Pure decisions for the update checker. The networking and persistence stay in
/// the app layer; this captures the branchy policy (the 24h gate and the
/// "should we surface this release" rule) so it can be unit-tested in isolation.
public enum UpdatePolicy {
    /// Whether an automatic check should run now: only when enabled, and only if
    /// we've never checked or the last check is at least `interval` ago.
    public static func shouldAutoCheck(
        autoEnabled: Bool,
        lastChecked: Date?,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard autoEnabled else { return false }
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= interval
    }

    /// Whether a fetched release should be shown to the user: it must be strictly
    /// newer than the current build and not the version the user dismissed.
    public static func shouldSurface(
        fetchedVersion: String,
        currentVersion: String,
        dismissedVersion: String?
    ) -> Bool {
        isVersion(fetchedVersion, newerThan: currentVersion)
            && fetchedVersion != dismissedVersion
    }
}
