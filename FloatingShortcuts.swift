import AppIntents
import Foundation

@available(iOS 17.0, *)
struct ToggleFloatingIntent: AppIntent {
    static var title: LocalizedStringResource = "切换图片悬浮"
    static var description = IntentDescription("在后台开启或关闭 TrollCrosshair 图片悬浮。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let succeeded = await MainActor.run {
            FloatingController.shared().performShortcutCommand("toggle")
        }
        return .result(value: succeeded)
    }
}

@available(iOS 17.0, *)
struct EnableFloatingIntent: AppIntent {
    static var title: LocalizedStringResource = "开启图片悬浮"
    static var description = IntentDescription("在后台开启 TrollCrosshair 图片悬浮。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let succeeded = await MainActor.run {
            FloatingController.shared().performShortcutCommand("on")
        }
        return .result(value: succeeded)
    }
}

@available(iOS 17.0, *)
struct DisableFloatingIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭图片悬浮"
    static var description = IntentDescription("在后台关闭 TrollCrosshair 图片悬浮。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let succeeded = await MainActor.run {
            FloatingController.shared().performShortcutCommand("off")
        }
        return .result(value: succeeded)
    }
}

@available(iOS 17.0, *)
struct FloatingAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleFloatingIntent(), phrases: [
            "切换图片悬浮，使用\(.applicationName)",
            "悬浮开关，使用\(.applicationName)"
        ], shortTitle: "悬浮开关", systemImageName: "rectangle.on.rectangle")
        AppShortcut(intent: EnableFloatingIntent(), phrases: [
            "开启图片悬浮，使用\(.applicationName)"
        ], shortTitle: "开启悬浮", systemImageName: "rectangle.on.rectangle")
        AppShortcut(intent: DisableFloatingIntent(), phrases: [
            "关闭图片悬浮，使用\(.applicationName)"
        ], shortTitle: "关闭悬浮", systemImageName: "rectangle.slash")
    }
}
