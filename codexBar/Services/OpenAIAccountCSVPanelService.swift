import AppKit
import Foundation

@MainActor
struct OpenAIAccountCSVPanelService {
    func requestExportURL() -> URL? {
        guard self.confirmSensitiveExport() else { return nil }

        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = L.exportOpenAICSVAction
        panel.prompt = L.openAICSVExportPrompt
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = false
        panel.allowedFileTypes = ["csv"]
        panel.nameFieldStringValue = self.defaultExportFilename()
        return panel.runModal() == .OK ? panel.url : nil
    }

    func requestImportURL() -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = L.importOpenAICSVAction
        panel.prompt = L.openAICSVImportPrompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        panel.allowedFileTypes = ["csv"]
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func confirmSensitiveExport() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.openAICSVRiskTitle
        alert.informativeText = L.openAICSVRiskMessage
        alert.addButton(withTitle: L.openAICSVRiskConfirm)
        alert.addButton(withTitle: L.cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func defaultExportFilename(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "openai-accounts-\(formatter.string(from: now)).csv"
    }
}
