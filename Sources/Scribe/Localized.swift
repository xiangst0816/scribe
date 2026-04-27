import Foundation

/// Lightweight, dictionary-based UI localization. Strings here cover the
/// status-bar menu, alerts and the LLM settings window. Native-language
/// labels (e.g. "中文 (简体)") are not routed through here.
///
/// Bucket selection follows the user's chosen speech locale; "System Default"
/// falls back to `Locale.preferredLanguages`.
enum L10n {
    /// Active translation bucket. Mutated via `setLanguage(localeCode:)`.
    private(set) static var current: String = preferredBucket()

    static func t(_ key: String) -> String {
        return strings[current]?[key] ?? strings["en"]?[key] ?? key
    }

    /// `localeCode` is a BCP-47 tag from the menu (e.g. "zh-CN"). Empty string
    /// means "System Default" — fall back to the OS preferred languages.
    static func setLanguage(localeCode: String) {
        current = localeCode.isEmpty ? preferredBucket() : bucket(for: localeCode)
    }

    private static func bucket(for code: String) -> String {
        let lower = code.lowercased()
        if lower.hasPrefix("zh-hant") || lower == "zh-tw" || lower == "zh-hk" || lower == "zh-mo" {
            return "zh-Hant"
        }
        if lower.hasPrefix("zh") { return "zh-Hans" }
        if lower.hasPrefix("ja") { return "ja" }
        if lower.hasPrefix("ko") { return "ko" }
        return "en"
    }

    private static func preferredBucket() -> String {
        for lang in Locale.preferredLanguages {
            let b = bucket(for: lang)
            if strings[b] != nil { return b }
        }
        return "en"
    }

    private static let strings: [String: [String: String]] = [
        "en": [
            // Menu
            "menu.enabled":            "Enabled",
            "menu.language":           "Language",
            "menu.systemDefault":      "System Default",
            "menu.checkForUpdates":    "Check for Updates…",
            "menu.quit":               "Quit Scribe",
            // Alerts
            "alert.permissionRequired":      "Permission Required",
            "alert.languageUnavailable":     "Language Unavailable",
            "alert.accessibilityTitle":      "Accessibility Permission Required",
            "alert.accessibilityBody":       """
                Scribe needs Accessibility permission to monitor the Fn key.

                1. Open System Settings → Privacy & Security → Accessibility
                2. Add Scribe and toggle it on
                3. Return to this app — it will retry automatically
                """,
            "alert.openSystemSettings":      "Open System Settings",
            "alert.later":                   "Later",
            "alert.ok":                      "OK",
            // Settings window
            "settings.title":          "LLM Refinement Settings",
            "settings.apiBaseURL":     "API Base URL:",
            "settings.apiKey":         "API Key:",
            "settings.model":          "Model:",
            "settings.test":           "Test",
            "settings.save":           "Save",
            "settings.apiKeyEmpty":    "API key is empty",
            "settings.testing":        "Testing...",
            "settings.testOK":         "OK: %@",
        ],
        "zh-Hans": [
            "menu.enabled":            "启用",
            "menu.language":           "语言",
            "menu.systemDefault":      "跟随系统",
            "menu.checkForUpdates":    "检查更新…",
            "menu.quit":               "退出 Scribe",
            "alert.permissionRequired":  "需要授权",
            "alert.languageUnavailable": "语言不可用",
            "alert.accessibilityTitle":  "需要辅助功能权限",
            "alert.accessibilityBody":   """
                Scribe 需要辅助功能权限来监听 Fn 键。

                1. 打开 系统设置 → 隐私与安全性 → 辅助功能
                2. 添加 Scribe 并开启开关
                3. 返回本应用 — 将自动重试
                """,
            "alert.openSystemSettings": "打开系统设置",
            "alert.later":              "稍后",
            "alert.ok":                 "好",
            "settings.title":          "大模型润色设置",
            "settings.apiBaseURL":     "API 地址：",
            "settings.apiKey":         "API 密钥：",
            "settings.model":          "模型：",
            "settings.test":           "测试",
            "settings.save":           "保存",
            "settings.apiKeyEmpty":    "API 密钥为空",
            "settings.testing":        "测试中…",
            "settings.testOK":         "成功：%@",
        ],
        "zh-Hant": [
            "menu.enabled":            "啟用",
            "menu.language":           "語言",
            "menu.systemDefault":      "跟隨系統",
            "menu.checkForUpdates":    "檢查更新…",
            "menu.quit":               "結束 Scribe",
            "alert.permissionRequired":  "需要授權",
            "alert.languageUnavailable": "語言不可用",
            "alert.accessibilityTitle":  "需要輔助使用權限",
            "alert.accessibilityBody":   """
                Scribe 需要輔助使用權限以監聽 Fn 鍵。

                1. 開啟 系統設定 → 隱私權與安全性 → 輔助使用
                2. 加入 Scribe 並開啟開關
                3. 回到本應用 — 將自動重試
                """,
            "alert.openSystemSettings": "開啟系統設定",
            "alert.later":              "稍後",
            "alert.ok":                 "好",
            "settings.title":          "大模型潤飾設定",
            "settings.apiBaseURL":     "API 位址：",
            "settings.apiKey":         "API 金鑰：",
            "settings.model":          "模型：",
            "settings.test":           "測試",
            "settings.save":           "儲存",
            "settings.apiKeyEmpty":    "API 金鑰為空",
            "settings.testing":        "測試中…",
            "settings.testOK":         "成功：%@",
        ],
        "ja": [
            "menu.enabled":            "有効",
            "menu.language":           "言語",
            "menu.systemDefault":      "システム設定に従う",
            "menu.checkForUpdates":    "アップデートを確認…",
            "menu.quit":               "Scribe を終了",
            "alert.permissionRequired":  "アクセス許可が必要です",
            "alert.languageUnavailable": "言語が利用できません",
            "alert.accessibilityTitle":  "アクセシビリティの許可が必要です",
            "alert.accessibilityBody":   """
                Scribe は Fn キーを監視するためにアクセシビリティ権限が必要です。

                1. システム設定 → プライバシーとセキュリティ → アクセシビリティ を開く
                2. Scribe を追加してオンに切り替える
                3. 本アプリに戻る — 自動的に再試行されます
                """,
            "alert.openSystemSettings": "システム設定を開く",
            "alert.later":              "あとで",
            "alert.ok":                 "OK",
            "settings.title":          "LLM 整形設定",
            "settings.apiBaseURL":     "API ベース URL:",
            "settings.apiKey":         "API キー:",
            "settings.model":          "モデル:",
            "settings.test":           "テスト",
            "settings.save":           "保存",
            "settings.apiKeyEmpty":    "API キーが空です",
            "settings.testing":        "テスト中…",
            "settings.testOK":         "成功: %@",
        ],
        "ko": [
            "menu.enabled":            "사용",
            "menu.language":           "언어",
            "menu.systemDefault":      "시스템 기본값",
            "menu.checkForUpdates":    "업데이트 확인…",
            "menu.quit":               "Scribe 종료",
            "alert.permissionRequired":  "권한이 필요합니다",
            "alert.languageUnavailable": "언어를 사용할 수 없습니다",
            "alert.accessibilityTitle":  "손쉬운 사용 권한이 필요합니다",
            "alert.accessibilityBody":   """
                Scribe가 Fn 키를 감지하려면 손쉬운 사용 권한이 필요합니다.

                1. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 열기
                2. Scribe를 추가하고 켜기
                3. 이 앱으로 돌아오면 자동으로 재시도합니다
                """,
            "alert.openSystemSettings": "시스템 설정 열기",
            "alert.later":              "나중에",
            "alert.ok":                 "확인",
            "settings.title":          "LLM 다듬기 설정",
            "settings.apiBaseURL":     "API 기본 URL:",
            "settings.apiKey":         "API 키:",
            "settings.model":          "모델:",
            "settings.test":           "테스트",
            "settings.save":           "저장",
            "settings.apiKeyEmpty":    "API 키가 비어 있습니다",
            "settings.testing":        "테스트 중…",
            "settings.testOK":         "성공: %@",
        ],
    ]
}
