import Foundation
import DeviceCore

// Devices tab status text: derived from status + issue only; `message` never reaches the UI.
@MainActor
func runDeviceStatusChecks(_ check: (Bool, String) -> Void) {
    let allIssues: [DeviceReadIssue] = [.frameworkUnavailable, .subscriptionFailed, .notificationCleanupFailed,
                                        .readInProgress, .deviceUnreadable]
    let diagnostic = "DIAGNOSTIC-MESSAGE-FOR-CLI"
    let device = ConnectedDeviceSnapshot(id: "0", kind: .iPhone, batteryPercentage: 80)

    for language in AppLanguage.allCases {
        L10n.language = language
        let tag = language.rawValue

        let empty = VisibleMetrics.deviceStatus(DeviceSnapshot(status: .available, message: diagnostic))
        check(empty == DeviceStatusDisplay(status: L10n.noDeviceConnected, tone: .normal,
                                           detail: L10n.availableButEmptyDetail, steps: VisibleMetrics.connectSteps),
              "available without devices (\(tag))")
        let none = VisibleMetrics.deviceStatus(DeviceSnapshot(status: .noDevice, message: diagnostic))
        check(none?.status == L10n.noDeviceConnected && none?.detail == L10n.noDeviceDetail && none?.steps.count == 3,
              "no device (\(tag))")
        let locked = VisibleMetrics.deviceStatus(DeviceSnapshot(status: .requiresUnlockAndTrust, message: diagnostic))
        check(locked?.status == L10n.unlockAndTrustRequired && locked?.tone == .warning && locked?.detail == nil
                && locked?.steps == VisibleMetrics.unlockSteps,
              "unlock and trust (\(tag))")
        let unavailable = VisibleMetrics.deviceStatus(DeviceSnapshot(status: .unavailable, message: diagnostic))
        check(unavailable?.status == L10n.interfaceUnavailable && unavailable?.detail == L10n.unavailableDetail,
              "unavailable without issue (\(tag))")
        let timedOut = VisibleMetrics.deviceStatus(DeviceSnapshot(status: .timedOut, message: diagnostic))
        check(timedOut?.status == L10n.readTimedOut && timedOut?.detail == L10n.timedOutDetail, "plain timeout (\(tag))")

        // The issue sentence replaces the default explanation.
        let cleanup = VisibleMetrics.deviceStatus(DeviceSnapshot(status: .unavailable, message: diagnostic, issue: .notificationCleanupFailed))
        check(cleanup?.detail == L10n.deviceIssue(.notificationCleanupFailed), "cleanup failure issue text (\(tag))")
        let busy = VisibleMetrics.deviceStatus(DeviceSnapshot(status: .timedOut, message: diagnostic, issue: .readInProgress))
        check(busy?.status == L10n.readTimedOut && busy?.detail == L10n.deviceIssue(.readInProgress), "read in progress issue text (\(tag))")
        let noDeviceIssue = VisibleMetrics.deviceStatus(DeviceSnapshot(status: .noDevice, message: diagnostic, issue: .subscriptionFailed))
        check(noDeviceIssue?.tone == .warning && noDeviceIssue?.detail == L10n.deviceIssue(.subscriptionFailed),
              "issue with no device is a warning (\(tag))")

        // Cards replace the status block; an accompanying issue becomes a note under the cards.
        let withDevice = DeviceSnapshot(status: .available, devices: [device], message: diagnostic)
        check(VisibleMetrics.deviceStatus(withDevice) == nil && VisibleMetrics.deviceIssueNote(withDevice) == nil,
              "devices shown without status block (\(tag))")
        let withDeviceIssue = DeviceSnapshot(status: .available, devices: [device], message: diagnostic, issue: .deviceUnreadable)
        check(VisibleMetrics.deviceStatus(withDeviceIssue) == nil
                && VisibleMetrics.deviceIssueNote(withDeviceIssue) == L10n.deviceIssue(.deviceUnreadable),
              "issue note under device cards (\(tag))")
        check(VisibleMetrics.deviceIssueNote(DeviceSnapshot(status: .timedOut, message: diagnostic, issue: .readInProgress)) == nil,
              "no duplicate note when the status block shows the issue (\(tag))")

        // Never the CLI message, for any status/issue combination.
        let statuses: [DeviceReadStatus] = [.available, .noDevice, .requiresUnlockAndTrust, .unavailable, .timedOut]
        var issues: [DeviceReadIssue?] = [nil]
        for issue in allIssues { issues.append(issue) }
        for status in statuses {
            for issue in issues {
                let snapshot = DeviceSnapshot(status: status, message: diagnostic, issue: issue)
                let display = VisibleMetrics.deviceStatus(snapshot)
                let texts = [display?.status, display?.detail].compactMap { $0 } + (display?.steps ?? [])
                check(display != nil, "status block for \(status.rawValue)/\(issue?.rawValue ?? "nil") (\(tag))")
                check(!texts.contains { $0.contains(diagnostic) }, "message never shown \(status.rawValue)/\(issue?.rawValue ?? "nil") (\(tag))")
                check(texts.allSatisfy { !$0.isEmpty }, "no empty status text \(status.rawValue)/\(issue?.rawValue ?? "nil") (\(tag))")
            }
        }
    }

    // Each issue has its own sentence, in both languages, and the two languages differ.
    for issue in allIssues {
        L10n.language = .english
        let english = L10n.deviceIssue(issue)
        L10n.language = .simplifiedChinese
        let chinese = L10n.deviceIssue(issue)
        check(!english.isEmpty && !chinese.isEmpty && english != chinese, "issue \(issue.rawValue) translated")
        check(!containsCJK(english) && containsCJK(chinese), "issue \(issue.rawValue) language matches")
    }
    L10n.language = .english
    check(Set(allIssues.map { L10n.deviceIssue($0) }).count == allIssues.count, "issue sentences are distinct")
    check(L10n.deviceIssue(.notificationCleanupFailed).contains("Restart"), "cleanup failure asks for a restart")
    check(L10n.deviceIssue(.readInProgress).contains("Try again"), "read in progress asks to retry shortly")
}
