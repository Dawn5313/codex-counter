import Foundation

/// Bilingual string helper — detects system language at runtime, with user override.
enum L {
    /// nil = follow system, true = force Chinese, false = force English
    nonisolated static var languageOverride: Bool? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: "languageOverride") != nil else { return nil }
            return d.bool(forKey: "languageOverride")
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: "languageOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "languageOverride")
            }
        }
    }

    nonisolated static var zh: Bool {
        if let override = languageOverride { return override }
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        return lang.hasPrefix("zh")
    }

    // MARK: - Status Bar
    static var weeklyLimit: String { zh ? "周限额" : "Weekly Limit" }
    static var hourLimit: String   { zh ? "5h限额" : "5h Limit" }

    // MARK: - MenuBarView
    static var noAccounts: String      { zh ? "还没有账号"          : "No Accounts" }
    static var addAccountHint: String  { zh ? "点击下方 + 添加账号"   : "Tap + below to add an account" }
    static var refreshUsage: String    { zh ? "刷新用量"            : "Refresh Usage" }
    static var addAccount: String      { zh ? "添加账号"            : "Add Account" }
    static var openAICSVToolbar: String { zh ? "导入或导出 OpenAI CSV" : "Import or Export OpenAI CSV" }
    static var exportOpenAICSVAction: String { zh ? "导出 OpenAI CSV…" : "Export OpenAI CSV…" }
    static var importOpenAICSVAction: String { zh ? "导入 OpenAI CSV…" : "Import OpenAI CSV…" }
    static var openAICSVExportPrompt: String { zh ? "导出" : "Export" }
    static var openAICSVImportPrompt: String { zh ? "导入" : "Import" }
    static var openAICSVRiskTitle: String { zh ? "导出将包含敏感 OAuth token" : "Export Includes Sensitive OAuth Tokens" }
    static var openAICSVRiskMessage: String {
        zh
            ? "导出的 CSV 将包含 access_token、refresh_token 和 id_token。请仅保存到受信任位置，避免分享或同步到不安全环境。"
            : "The exported CSV includes access_token, refresh_token, and id_token. Save it only to a trusted location and avoid sharing or syncing it to insecure destinations."
    }
    static var openAICSVRiskConfirm: String { zh ? "继续导出" : "Export Anyway" }
    static var noOpenAIAccountsToExport: String {
        zh ? "没有可导出的 OpenAI 账号" : "No OpenAI accounts available to export"
    }
    static func openAICSVExportSucceeded(_ count: Int) -> String {
        zh ? "已导出 \(count) 个 OpenAI 账号到 CSV。" : "Exported \(count) OpenAI account\(count == 1 ? "" : "s") to CSV."
    }
    static func openAICSVImportSucceeded(
        added: Int,
        updated: Int,
        activeChanged: Bool,
        providerChanged: Bool,
        preservedCompatibleProvider: Bool
    ) -> String {
        let prefix = zh
            ? "已导入 OpenAI CSV：新增 \(added) 个，覆盖 \(updated) 个。"
            : "Imported OpenAI CSV: \(added) added, \(updated) updated."
        let suffix: String
        if preservedCompatibleProvider {
            suffix = zh ? " 当前使用 provider 保持不变。" : " The current provider was left unchanged."
        } else if providerChanged {
            suffix = zh ? " 当前 provider 已切换到 OpenAI。" : " The current provider was switched to OpenAI."
        } else if activeChanged {
            suffix = zh ? " 当前 OpenAI 账号已更新。" : " The current OpenAI account was updated."
        } else {
            suffix = zh ? " 当前 active 选择未变化。" : " The current active selection was unchanged."
        }
        return prefix + suffix
    }
    static var openAICSVEmptyFile: String { zh ? "CSV 为空，或只有表头。" : "The CSV is empty or only contains a header." }
    static var openAICSVMissingColumns: String { zh ? "CSV 缺少必需列。" : "The CSV is missing required columns." }
    static var openAICSVUnsupportedVersion: String { zh ? "不支持的 CSV 版本。" : "Unsupported CSV format version." }
    static func openAICSVInvalidRow(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行格式无效。" : "CSV row \(row) has an invalid format."
    }
    static func openAICSVMissingRequiredValue(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行缺少必填字段。" : "CSV row \(row) is missing required fields."
    }
    static func openAICSVInvalidAccount(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 token 校验失败。" : "CSV row \(row) failed token validation."
    }
    static func openAICSVAccountIDMismatch(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 account_id 校验失败。" : "CSV row \(row) failed account_id validation."
    }
    static func openAICSVEmailMismatch(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 email 校验失败。" : "CSV row \(row) failed email validation."
    }
    static var openAICSVDuplicateAccounts: String { zh ? "CSV 中存在重复的 account_id。" : "The CSV contains duplicate account_id values." }
    static var openAICSVMultipleActiveAccounts: String { zh ? "CSV 中包含多个 is_active=true 的账号。" : "The CSV contains multiple accounts marked as is_active=true." }
    static func openAICSVInvalidActiveValue(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 is_active 值无效。" : "CSV row \(row) has an invalid is_active value."
    }
    static var quit: String            { zh ? "退出"               : "Quit" }
    static var switchAccount: String    { zh ? "切换账号"            : "Switch Account" }
    static var switchTitle: String     { zh ? "切换账号"            : "Switch Account" }
    static var continueRestart: String { zh ? "继续"               : "Continue" }
    static var cancel: String          { zh ? "取消"               : "Cancel" }
    static var justUpdated: String     { zh ? "刚刚更新"            : "Just updated" }
    static var restartCodexTitle: String {
        zh ? "Codex.app 正在运行" : "Codex.app is Running"
    }
    static var restartCodexInfo: String {
        zh
            ? "账号已切换完成。\n\n如需立即生效，可强制退出 Codex.app（可选是否自动重新打开）。\n\n⚠️ 警告：强制退出将终止所有 subagent 任务，可能导致进行中的任务丢失，请谨慎操作。"
            : "Account switched successfully.\n\nYou may force-quit Codex.app now to apply the change (optionally reopen it).\n\n⚠️ Warning: Force-quitting will kill all running subagent tasks. Make sure no important tasks are in progress."
    }
    static var forceQuitAndReopen: String { zh ? "强制退出并重新打开" : "Force Quit & Reopen" }
    static var forceQuitOnly: String    { zh ? "仅强制退出" : "Force Quit Only" }
    static var restartLater: String     { zh ? "稍后手动重启" : "Later" }

    static func available(_ n: Int, _ total: Int) -> String {
        zh ? "\(n)/\(total) 可用" : "\(n)/\(total) Available"
    }
    static func minutesAgo(_ m: Int) -> String {
        zh ? "\(m) 分钟前更新" : "Updated \(m) min ago"
    }
    static func hoursAgo(_ h: Int) -> String {
        zh ? "\(h) 小时前更新" : "Updated \(h) hr ago"
    }
    static var switchWarningTitle: String {
        zh ? "⚠️ 实验性功能 — 账号切换" : "⚠️ Experimental — Account Switch"
    }
    static func switchConfirm(_ name: String) -> String { switchWarning(name) }
    static func switchConfirmMsg(_ name: String) -> String { switchWarning(name) }
    static func switchWarning(_ name: String) -> String {
        zh
            ? "⚠️ 实验性功能\n\n将切换到「\(name)」。\n\n此功能通过直接修改配置文件实现辅助切换，需要退出整个 Codex.app 才能生效。退出过程中可能导致数据丢失！\n\n如果你正在使用 subagent，强烈建议通过软件内的退出登录功能重新登录其他账号，而非使用此切换方案。"
            : "⚠️ Experimental Feature\n\nSwitching to \"\(name)\".\n\nThis feature works by modifying the config file directly. Codex.app must be fully quit to apply the change, which may cause data loss.\n\nIf you are using subagents, it is strongly recommended to log out from within Codex.app and log in with another account instead."
    }

    // MARK: - Auto switch
    static var autoSwitchTitle: String {
        zh ? "已自动切换账号" : "Account Auto-Switched"
    }
    static func autoSwitchBody(_ from: String, _ to: String) -> String {
        zh
            ? "「\(from)」额度不足，已自动切换至「\(to)」"
            : "Quota low on \"\(from)\", switched to \"\(to)\""
    }
    static var autoSwitchNoCandidates: String {
        zh
            ? "所有账号额度不足或不可用，请手动处理"
            : "All accounts are low or unavailable, please take action"
    }

    // MARK: - AccountRowView
    static var reauth: String          { zh ? "重新授权"     : "Re-authorize" }
    static var useBtn: String          { zh ? "使用"         : "Use" }
    static var switchBtn: String       { useBtn }
    static var tokenExpiredMsg: String { zh ? "Token 已过期，请重新授权" : "Token expired, please re-authorize" }
    static var bannedMsg: String       { zh ? "账号已停用"   : "Account suspended" }
    static var deleteBtn: String       { zh ? "删除"         : "Delete" }
    static var deleteConfirm: String   { zh ? "删除"         : "Delete" }
    static var nextUseTitle: String    { zh ? "下一次使用"   : "Next Use" }
    static var inUseNone: String       { zh ? "未检测到正在使用的 OpenAI 会话" : "No live OpenAI sessions detected" }

    static func inUseSessions(_ count: Int) -> String {
        zh ? "使用中 · \(count) 个会话" : "In Use · \(count) session\(count == 1 ? "" : "s")"
    }

    static func inUseSummary(_ sessions: Int, _ accounts: Int) -> String {
        if zh {
            return "使用中 · \(sessions) 个会话 / \(accounts) 个账号"
        }
        return "In Use · \(sessions) session\(sessions == 1 ? "" : "s") across \(accounts) account\(accounts == 1 ? "" : "s")"
    }

    static func inUseUnknownSessions(_ count: Int) -> String {
        zh ? "另有 \(count) 个未归因会话" : "\(count) unattributed session\(count == 1 ? "" : "s")"
    }

    static func deletePrompt(_ name: String) -> String {
        zh ? "确认删除 \(name)？" : "Delete \(name)?"
    }
    static func confirmDelete(_ name: String) -> String { deletePrompt(name) }
    static var delete: String         { zh ? "删除"     : "Delete" }
    static var tokenExpiredHint: String { zh ? "Token 已过期，请重新授权" : "Token expired, please re-authorize" }
    static var accountSuspended: String { zh ? "账号已停用" : "Account suspended" }
    static var weeklyExhausted: String  { zh ? "周额度耗尽" : "Weekly quota exhausted" }
    static var primaryExhausted: String { zh ? "5h 额度耗尽" : "5h quota exhausted" }
    nonisolated static func compactResetDaysHours(_ days: Int, _ hours: Int) -> String {
        zh ? "\(days)天\(hours)时" : "\(days)d \(hours)h"
    }
    nonisolated static func compactResetHoursMinutes(_ hours: Int, _ minutes: Int) -> String {
        zh ? "\(hours)时\(minutes)分" : "\(hours)h \(minutes)m"
    }
    nonisolated static func compactResetMinutes(_ minutes: Int) -> String {
        zh ? "\(minutes)分" : "\(minutes)m"
    }
    nonisolated static var compactResetSoon: String {
        zh ? "1分内" : "<1m"
    }

    // MARK: - TokenAccount status
    static var statusOk: String       { zh ? "正常"     : "OK" }
    static var statusWarning: String  { zh ? "即将用尽" : "Warning" }
    static var statusExceeded: String { zh ? "额度耗尽" : "Exceeded" }
    static var statusBanned: String   { zh ? "已停用"   : "Suspended" }

    // MARK: - Reset countdown
    static var resetSoon: String { zh ? "即将重置" : "Resetting soon" }
    static func resetInMin(_ m: Int) -> String {
        zh ? "\(m) 分钟后重置" : "Resets in \(m) min"
    }
    static func resetInHr(_ h: Int, _ m: Int) -> String {
        zh ? "\(h) 小时 \(m) 分后重置" : "Resets in \(h)h \(m)m"
    }
    static func resetInDay(_ d: Int, _ h: Int) -> String {
        zh ? "\(d) 天 \(h) 小时后重置" : "Resets in \(d)d \(h)h"
    }
}
