import SwiftUI
import ServiceManagement
import HelioCore

struct SettingsView: View {
    @AppStorage("age") private var age = 30
    @AppStorage("restingHR") private var restingHR = 0
    @AppStorage("alertEnabled") private var alertEnabled = false
    @AppStorage("alertThreshold") private var alertThreshold = 100
    @AppStorage("alertDurationMin") private var alertDurationMin = 3
    @AppStorage("lowHRAlertEnabled") private var lowHRAlertEnabled = false
    @AppStorage("lowHRThreshold") private var lowHRThreshold = 45
    @AppStorage("lowHRDurationMin") private var lowHRDurationMin = 2
    @AppStorage("batteryAlertEnabled") private var batteryAlertEnabled = true
    @AppStorage("batteryAlertThreshold") private var batteryAlertThreshold = 20
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    let updater: UpdateChecker
    @State private var launchAtLogin = Self.isLaunchOn
    @State private var needsApproval = (SMAppService.mainApp.status == .requiresApproval)
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Stepper("Age: \(age)", value: $age, in: 10...100)
                Text("Max HR ≈ \(maxHR(forAge: age)) bpm · zones scale to this")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Resting HR: \(restingHR == 0 ? "off" : "\(restingHR) bpm")",
                        value: $restingHR, in: 0...100, step: 1)
                Text(restingHR == 0
                     ? "Set your resting HR for more personal zones (heart-rate reserve)."
                     : "Zones use heart-rate reserve: (HR − \(restingHR)) / (\(maxHR(forAge: age)) − \(restingHR)).")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Label("You", systemImage: "person.fill")
            }
            Section {
                Toggle("Notify when HR stays high", isOn: $alertEnabled)
                Stepper("Above \(alertThreshold) bpm", value: $alertThreshold, in: 80...200, step: 5)
                Stepper("For \(alertDurationMin) min", value: $alertDurationMin, in: 1...30)
            } header: {
                Label("Elevated-HR alert", systemImage: "heart.text.square.fill")
            }
            Section {
                Toggle("Notify when HR stays low", isOn: $lowHRAlertEnabled)
                Stepper("Below \(lowHRThreshold) bpm", value: $lowHRThreshold, in: 30...80, step: 5)
                Stepper("For \(lowHRDurationMin) min", value: $lowHRDurationMin, in: 1...30)
            } header: {
                Label("Low-HR alert", systemImage: "heart.slash.fill")
            }
            Section {
                Toggle("Notify when strap battery is low", isOn: $batteryAlertEnabled)
                Stepper("At or below \(batteryAlertThreshold)%", value: $batteryAlertThreshold, in: 5...50, step: 5)
            } header: {
                Label("Strap battery alert", systemImage: "battery.25percent")
            }
            Section {
                Toggle("Check for updates automatically", isOn: $autoUpdateCheck)
                HStack {
                    Button("Check now") { Task { await updater.checkNow() } }
                    Spacer()
                    Text(updateStatusText).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Label("Updates", systemImage: "arrow.down.circle")
            }
            Section {
                // Custom binding so only user taps drive register/unregister;
                // a programmatic refresh of `launchAtLogin` must not re-fire it.
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunch($0) }))
                if needsApproval {
                    Text("Approve HelioBar in Login Items to finish enabling this.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    .controlSize(.small)
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Label("System", systemImage: "power")
            }
        }
        .formStyle(.grouped)
        .frame(width: 330, height: 400)
        .onAppear(perform: refreshLaunchStatus)
    }

    /// Treat "requires approval" as on: the user opted in; macOS just needs a
    /// confirmation in System Settings before it takes effect.
    private static var isLaunchOn: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    private var updateStatusText: String {
        switch updater.status {
        case .checking: return "Checking…"
        case .failed:   return "Couldn't check"
        case .upToDate: return "Up to date"
        case .idle:
            if updater.available != nil { return "Update available" }
            if let d = updater.lastChecked {
                let f = RelativeDateTimeFormatter()
                return "Checked \(f.localizedString(for: d, relativeTo: Date()))"
            }
            return ""
        }
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchStatus()
    }

    /// Reflect the live SMAppService state. `.requiresApproval` keeps the toggle
    /// on (the user opted in) and shows the approval hint instead of silently
    /// bouncing the toggle back off.
    private func refreshLaunchStatus() {
        let status = SMAppService.mainApp.status
        needsApproval = (status == .requiresApproval)
        launchAtLogin = (status == .enabled || status == .requiresApproval)
    }
}
