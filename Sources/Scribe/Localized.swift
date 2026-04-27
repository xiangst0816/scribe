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
            "menu.voiceQuality":       "Voice Quality",
            "menu.checkForUpdates":    "Check for Updates…",
            "menu.quit":               "Quit Scribe",
            // Voice quality names
            "quality.system":          "System",
            "quality.fast":            "Fast",
            "quality.balanced":        "Balanced",
            "quality.high":            "High Quality",
            // Quality row suffixes
            "quality.suffix.download":  "Download",
            "quality.suffix.downloading": "Downloading %d%%",
            "quality.suffix.ready":     "Ready",
            "quality.suffix.loading":   "Loading…",
            "quality.suffix.loadingElapsed": "Loading… %ds",
            "quality.suffix.inUse":     "In Use",
            "quality.suffix.failed":    "Failed — click to retry",
            // Status info line
            "status.notDownloaded":     "Not downloaded",
            "status.downloadingFallback": "Downloading %d%% — using fallback",
            "status.ready":             "Ready",
            "status.loadingModel":      "Loading model…",
            "status.loadingModelElapsed": "Loading model… %ds",
            "status.active":            "Active",
            "status.failedRetrySuffix": "%@ — click to retry",
            // Model errors (surfaced in menu)
            "error.downloadFailed":     "Download failed",
            "error.loadFailed":         "Load failed",
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
            "menu.voiceQuality":       "语音质量",
            "menu.checkForUpdates":    "检查更新…",
            "menu.quit":               "退出 Scribe",
            "quality.system":          "系统",
            "quality.fast":            "快速",
            "quality.balanced":        "均衡",
            "quality.high":            "高质量",
            "quality.suffix.download": "下载",
            "quality.suffix.downloading": "下载中 %d%%",
            "quality.suffix.ready":    "已就绪",
            "quality.suffix.loading":  "加载中…",
            "quality.suffix.loadingElapsed": "加载中… %d 秒",
            "quality.suffix.inUse":    "使用中",
            "quality.suffix.failed":   "失败 — 点击重试",
            "status.notDownloaded":    "未下载",
            "status.downloadingFallback": "下载中 %d%% — 暂用系统识别",
            "status.ready":            "已就绪",
            "status.loadingModel":     "正在加载模型…",
            "status.loadingModelElapsed": "正在加载模型… %d 秒",
            "status.active":           "已启用",
            "status.failedRetrySuffix": "%@ — 点击重试",
            "error.downloadFailed":    "下载失败",
            "error.loadFailed":        "加载失败",
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
            "menu.voiceQuality":       "語音品質",
            "menu.checkForUpdates":    "檢查更新…",
            "menu.quit":               "結束 Scribe",
            "quality.system":          "系統",
            "quality.fast":            "快速",
            "quality.balanced":        "平衡",
            "quality.high":            "高品質",
            "quality.suffix.download": "下載",
            "quality.suffix.downloading": "下載中 %d%%",
            "quality.suffix.ready":    "已就緒",
            "quality.suffix.loading":  "載入中…",
            "quality.suffix.loadingElapsed": "載入中… %d 秒",
            "quality.suffix.inUse":    "使用中",
            "quality.suffix.failed":   "失敗 — 點擊重試",
            "status.notDownloaded":    "尚未下載",
            "status.downloadingFallback": "下載中 %d%% — 暫用系統辨識",
            "status.ready":            "已就緒",
            "status.loadingModel":     "正在載入模型…",
            "status.loadingModelElapsed": "正在載入模型… %d 秒",
            "status.active":           "已啟用",
            "status.failedRetrySuffix": "%@ — 點擊重試",
            "error.downloadFailed":    "下載失敗",
            "error.loadFailed":        "載入失敗",
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
            "menu.voiceQuality":       "音声品質",
            "menu.checkForUpdates":    "アップデートを確認…",
            "menu.quit":               "Scribe を終了",
            "quality.system":          "システム",
            "quality.fast":            "高速",
            "quality.balanced":        "バランス",
            "quality.high":            "高品質",
            "quality.suffix.download": "ダウンロード",
            "quality.suffix.downloading": "ダウンロード中 %d%%",
            "quality.suffix.ready":    "準備完了",
            "quality.suffix.loading":  "読み込み中…",
            "quality.suffix.loadingElapsed": "読み込み中… %d秒",
            "quality.suffix.inUse":    "使用中",
            "quality.suffix.failed":   "失敗 — クリックで再試行",
            "status.notDownloaded":    "未ダウンロード",
            "status.downloadingFallback": "ダウンロード中 %d%% — 暫定で代替認識を使用",
            "status.ready":            "準備完了",
            "status.loadingModel":     "モデルを読み込み中…",
            "status.loadingModelElapsed": "モデルを読み込み中… %d秒",
            "status.active":           "有効",
            "status.failedRetrySuffix": "%@ — クリックで再試行",
            "error.downloadFailed":    "ダウンロードに失敗しました",
            "error.loadFailed":        "読み込みに失敗しました",
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
            "menu.voiceQuality":       "음성 품질",
            "menu.checkForUpdates":    "업데이트 확인…",
            "menu.quit":               "Scribe 종료",
            "quality.system":          "시스템",
            "quality.fast":            "빠름",
            "quality.balanced":        "균형",
            "quality.high":            "고품질",
            "quality.suffix.download": "다운로드",
            "quality.suffix.downloading": "다운로드 중 %d%%",
            "quality.suffix.ready":    "준비됨",
            "quality.suffix.loading":  "로드 중…",
            "quality.suffix.loadingElapsed": "로드 중… %d초",
            "quality.suffix.inUse":    "사용 중",
            "quality.suffix.failed":   "실패 — 클릭하여 재시도",
            "status.notDownloaded":    "다운로드되지 않음",
            "status.downloadingFallback": "다운로드 중 %d%% — 임시 인식기 사용",
            "status.ready":            "준비됨",
            "status.loadingModel":     "모델 로드 중…",
            "status.loadingModelElapsed": "모델 로드 중… %d초",
            "status.active":           "사용 중",
            "status.failedRetrySuffix": "%@ — 클릭하여 재시도",
            "error.downloadFailed":    "다운로드 실패",
            "error.loadFailed":        "로드 실패",
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
