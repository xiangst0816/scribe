import Foundation

/// Lightweight, dictionary-based UI localization. Strings here cover the
/// status-bar menu, alerts, and the Polish settings window. Native-language
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
            "menu.microphone":         "Microphone",
            "menu.mic.auto":           "Auto (Follow Output Device)",
            "menu.checkForUpdates":    "Check for Updates…",
            "menu.settings":           "Settings…",
            "menu.quit":               "Quit Scribe",
            // Status-bar Polish state
            "menu.polish.off":             "Polish: Off",
            "menu.polish.readySystem":     "Polish: Ready (System)",
            "menu.polish.readyLocal":      "Polish: Ready (Local)",
            "menu.polish.skipped":         "Polish: Skipped last call",
            "menu.polish.skippedTimeout":  "Polish: Skipped last call (timed out)",
            "menu.polish.unavailable":     "Polish: Unavailable",
            "menu.polish.breakerTripped":  "Polish: Disabled after repeated failures",
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
            "alert.polishBreakerTitle":      "Polish disabled",
            "alert.polishBreakerBody":       "Transcript polishing failed three times in a row and has been turned off. The recording was pasted unchanged. You can re-enable polishing in Settings.",
            // Polish settings window
            "settings.title":                  "Polish Settings",
            "settings.polish.enable":          "Enable transcript polishing",
            "settings.polish.description":    "Cleans up filler words, false starts, and disfluencies. Runs entirely on your Mac.",
            "settings.polish.engine":          "Engine:",
            "settings.polish.system.label":    "System on-device model (Apple Intelligence)",
            "settings.polish.system.detail":   "No download. Fastest. Recommended when available.",
            "settings.polish.local.label":     "Scribe local model (Gemma 4 E2B, ~3.5 GB download)",
            "settings.polish.local.detail":    "Works on any Apple Silicon Mac.",
            "settings.polish.statusPrefix":    "Status: ",
            "settings.polish.download":        "Download…",
            "settings.polish.done":            "Done",
            // Polish — System backend status text
            "polish.system.statusAvailable":         "Ready",
            "polish.system.statusDeviceNotEligible": "Unavailable on this device — region not supported by Apple Intelligence",
            "polish.system.statusNotEnabled":        "Apple Intelligence is not enabled in System Settings",
            "polish.system.statusModelNotReady":     "Apple Intelligence model still preparing — try again later",
            "polish.system.statusUnavailable":       "Unavailable",
            "polish.system.statusRequiresMacOS26":   "Requires macOS 26 (Tahoe) or later",
            // Polish — Local backend status text
            "polish.local.statusReady":          "Ready",
            "polish.local.statusNotDownloaded":  "Not downloaded — click Download to fetch the model (~1 GB)",
            "polish.local.statusDownloading":    "Downloading… %d%%",
            "polish.local.statusVerifying":      "Verifying SHA-256…",
            "polish.local.statusFailed":         "Download failed",
            "polish.local.statusLoadFailed":     "Model failed to load",
            "polish.local.failNetwork":          "Could not reach any download mirror — check your network",
            "polish.local.failMirror":           "All mirrors returned an error",
            "polish.local.failIntegrity":       "Hash mismatch — file rejected",
            "polish.local.failNotPinned":       "This build does not yet ship a pinned model hash",
            "polish.local.failDiskFull":        "Out of disk space",
            "polish.local.failIO":              "I/O error",
            "settings.polish.cancel":            "Cancel",
            "settings.polish.delete":            "Delete model file",
            "settings.polish.mirror":            "Mirror:",
            "settings.polish.mirror.auto":       "Auto",
        ],
        "zh-Hans": [
            "menu.enabled":            "启用",
            "menu.language":           "语言",
            "menu.systemDefault":      "跟随系统",
            "menu.microphone":         "麦克风",
            "menu.mic.auto":           "自动（跟随输出设备）",
            "menu.checkForUpdates":    "检查更新…",
            "menu.settings":           "设置…",
            "menu.quit":               "退出 Scribe",
            "menu.polish.off":             "润色：关闭",
            "menu.polish.readySystem":     "润色：就绪（系统）",
            "menu.polish.readyLocal":      "润色：就绪（本地）",
            "menu.polish.skipped":         "润色：上一次已跳过",
            "menu.polish.skippedTimeout":  "润色：上一次超时跳过",
            "menu.polish.unavailable":     "润色：不可用",
            "menu.polish.breakerTripped":  "润色：连续失败后已关闭",
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
            "alert.polishBreakerTitle": "润色已关闭",
            "alert.polishBreakerBody":  "转写润色连续失败三次，已自动关闭。本次录音按原文粘贴。可在设置中重新启用。",
            "settings.title":                  "润色设置",
            "settings.polish.enable":          "启用转写润色",
            "settings.polish.description":     "去除口头语、重复和断句问题。完全在本机运行。",
            "settings.polish.engine":          "引擎：",
            "settings.polish.system.label":    "系统内置模型（Apple Intelligence）",
            "settings.polish.system.detail":   "无需下载，速度最快。如可用则推荐使用。",
            "settings.polish.local.label":     "Scribe 本地模型（Gemma 4 E2B，需下载约 3.5 GB）",
            "settings.polish.local.detail":    "在任何 Apple Silicon Mac 上都能用。",
            "settings.polish.statusPrefix":    "状态：",
            "settings.polish.download":        "下载…",
            "settings.polish.done":            "完成",
            "polish.system.statusAvailable":         "已就绪",
            "polish.system.statusDeviceNotEligible": "本设备不可用 — 当前区域不支持 Apple Intelligence",
            "polish.system.statusNotEnabled":        "请在系统设置中开启 Apple Intelligence",
            "polish.system.statusModelNotReady":     "Apple Intelligence 模型仍在准备 — 稍后再试",
            "polish.system.statusUnavailable":       "不可用",
            "polish.system.statusRequiresMacOS26":   "需要 macOS 26（Tahoe）或更新版本",
            "polish.local.statusReady":          "已就绪",
            "polish.local.statusNotDownloaded":  "未下载 — 点击「下载」获取模型（约 1 GB）",
            "polish.local.statusDownloading":    "下载中… %d%%",
            "polish.local.statusVerifying":      "正在校验 SHA-256…",
            "polish.local.statusFailed":         "下载失败",
            "polish.local.statusLoadFailed":     "模型加载失败",
            "polish.local.failNetwork":          "无法连接任何下载镜像，请检查网络",
            "polish.local.failMirror":           "所有镜像都返回错误",
            "polish.local.failIntegrity":       "哈希不匹配 — 文件已拒绝",
            "polish.local.failNotPinned":       "此版本未固定模型哈希",
            "polish.local.failDiskFull":        "磁盘空间不足",
            "polish.local.failIO":              "I/O 错误",
            "settings.polish.cancel":            "取消",
            "settings.polish.delete":            "删除模型文件",
            "settings.polish.mirror":            "镜像：",
            "settings.polish.mirror.auto":       "自动",
        ],
        "zh-Hant": [
            "menu.enabled":            "啟用",
            "menu.language":           "語言",
            "menu.systemDefault":      "跟隨系統",
            "menu.microphone":         "麥克風",
            "menu.mic.auto":           "自動（跟隨輸出裝置）",
            "menu.checkForUpdates":    "檢查更新…",
            "menu.settings":           "設定…",
            "menu.quit":               "結束 Scribe",
            "menu.polish.off":             "潤飾：關閉",
            "menu.polish.readySystem":     "潤飾：就緒（系統）",
            "menu.polish.readyLocal":      "潤飾：就緒（本機）",
            "menu.polish.skipped":         "潤飾：上次已略過",
            "menu.polish.skippedTimeout":  "潤飾：上次逾時略過",
            "menu.polish.unavailable":     "潤飾：無法使用",
            "menu.polish.breakerTripped":  "潤飾：連續失敗後已停用",
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
            "alert.polishBreakerTitle": "潤飾已停用",
            "alert.polishBreakerBody":  "轉寫潤飾連續失敗三次，已自動停用。本次錄音以原文貼上。可在設定中重新啟用。",
            "settings.title":                  "潤飾設定",
            "settings.polish.enable":          "啟用轉寫潤飾",
            "settings.polish.description":     "移除贅詞、重複與斷句問題，完全在本機執行。",
            "settings.polish.engine":          "引擎：",
            "settings.polish.system.label":    "系統內建模型（Apple Intelligence）",
            "settings.polish.system.detail":   "無需下載，速度最快。可用時建議使用。",
            "settings.polish.local.label":     "Scribe 本機模型（Gemma 4 E2B，需下載約 3.5 GB）",
            "settings.polish.local.detail":    "支援任何 Apple Silicon Mac。",
            "settings.polish.statusPrefix":    "狀態：",
            "settings.polish.download":        "下載…",
            "settings.polish.done":            "完成",
            "polish.system.statusAvailable":         "已就緒",
            "polish.system.statusDeviceNotEligible": "本機無法使用 — 此地區不支援 Apple Intelligence",
            "polish.system.statusNotEnabled":        "請在系統設定中開啟 Apple Intelligence",
            "polish.system.statusModelNotReady":     "Apple Intelligence 模型仍在準備 — 稍後再試",
            "polish.system.statusUnavailable":       "無法使用",
            "polish.system.statusRequiresMacOS26":   "需要 macOS 26（Tahoe）或更新版本",
            "polish.local.statusReady":          "已就緒",
            "polish.local.statusNotDownloaded":  "尚未下載 — 點擊「下載」取得模型（約 1 GB）",
            "polish.local.statusDownloading":    "下載中… %d%%",
            "polish.local.statusVerifying":      "正在驗證 SHA-256…",
            "polish.local.statusFailed":         "下載失敗",
            "polish.local.statusLoadFailed":     "模型載入失敗",
            "polish.local.failNetwork":          "無法連接任何下載鏡像，請檢查網路",
            "polish.local.failMirror":           "所有鏡像都回傳錯誤",
            "polish.local.failIntegrity":       "雜湊不符 — 檔案已拒絕",
            "polish.local.failNotPinned":       "此版本尚未固定模型雜湊",
            "polish.local.failDiskFull":        "磁碟空間不足",
            "polish.local.failIO":              "I/O 錯誤",
            "settings.polish.cancel":            "取消",
            "settings.polish.delete":            "刪除模型檔案",
            "settings.polish.mirror":            "鏡像：",
            "settings.polish.mirror.auto":       "自動",
        ],
        "ja": [
            "menu.enabled":            "有効",
            "menu.language":           "言語",
            "menu.systemDefault":      "システム設定に従う",
            "menu.microphone":         "マイク",
            "menu.mic.auto":           "自動（出力デバイスに合わせる）",
            "menu.checkForUpdates":    "アップデートを確認…",
            "menu.settings":           "設定…",
            "menu.quit":               "Scribe を終了",
            "menu.polish.off":             "整形：オフ",
            "menu.polish.readySystem":     "整形：使用可能（システム）",
            "menu.polish.readyLocal":      "整形：使用可能（ローカル）",
            "menu.polish.skipped":         "整形：直前の処理をスキップしました",
            "menu.polish.skippedTimeout":  "整形：直前の処理がタイムアウトしました",
            "menu.polish.unavailable":     "整形：利用できません",
            "menu.polish.breakerTripped":  "整形：連続失敗のため無効になりました",
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
            "alert.polishBreakerTitle": "整形を無効にしました",
            "alert.polishBreakerBody":  "整形が 3 回連続で失敗したため自動的に無効になりました。今回の録音はそのまま貼り付けられました。設定から再度有効にできます。",
            "settings.title":                  "整形設定",
            "settings.polish.enable":          "文字起こしの整形を有効にする",
            "settings.polish.description":     "言い淀みや言い直し、不自然な言い回しを整えます。すべて Mac 内で処理されます。",
            "settings.polish.engine":          "エンジン:",
            "settings.polish.system.label":    "システム内蔵モデル（Apple Intelligence）",
            "settings.polish.system.detail":   "ダウンロード不要・最速。利用可能なら推奨。",
            "settings.polish.local.label":     "Scribe ローカルモデル（Gemma 4 E2B、約 3.5 GB のダウンロード）",
            "settings.polish.local.detail":    "Apple Silicon の Mac で動作します。",
            "settings.polish.statusPrefix":    "状態: ",
            "settings.polish.download":        "ダウンロード…",
            "settings.polish.done":            "完了",
            "polish.system.statusAvailable":         "利用可能",
            "polish.system.statusDeviceNotEligible": "このデバイスでは利用できません — お住まいの地域は Apple Intelligence 非対応です",
            "polish.system.statusNotEnabled":        "システム設定で Apple Intelligence をオンにしてください",
            "polish.system.statusModelNotReady":     "Apple Intelligence モデルの準備中です — しばらく経ってから再試行してください",
            "polish.system.statusUnavailable":       "利用できません",
            "polish.system.statusRequiresMacOS26":   "macOS 26（Tahoe）以降が必要です",
            "polish.local.statusReady":          "利用可能",
            "polish.local.statusNotDownloaded":  "未ダウンロード — 「ダウンロード」をクリックしてモデルを取得（約 1 GB）",
            "polish.local.statusDownloading":    "ダウンロード中… %d%%",
            "polish.local.statusVerifying":      "SHA-256 を検証中…",
            "polish.local.statusFailed":         "ダウンロード失敗",
            "polish.local.statusLoadFailed":     "モデルの読み込みに失敗",
            "polish.local.failNetwork":          "どのミラーにも接続できません — ネットワークを確認してください",
            "polish.local.failMirror":           "すべてのミラーがエラーを返しました",
            "polish.local.failIntegrity":       "ハッシュ不一致 — ファイルを拒否",
            "polish.local.failNotPinned":       "このビルドではモデルのハッシュが固定されていません",
            "polish.local.failDiskFull":        "ディスク容量不足",
            "polish.local.failIO":              "I/O エラー",
            "settings.polish.cancel":            "キャンセル",
            "settings.polish.delete":            "モデルファイルを削除",
            "settings.polish.mirror":            "ミラー:",
            "settings.polish.mirror.auto":       "自動",
        ],
        "ko": [
            "menu.enabled":            "사용",
            "menu.language":           "언어",
            "menu.systemDefault":      "시스템 기본값",
            "menu.microphone":         "마이크",
            "menu.mic.auto":           "자동(출력 장치를 따름)",
            "menu.checkForUpdates":    "업데이트 확인…",
            "menu.settings":           "설정…",
            "menu.quit":               "Scribe 종료",
            "menu.polish.off":             "다듬기: 꺼짐",
            "menu.polish.readySystem":     "다듬기: 준비됨(시스템)",
            "menu.polish.readyLocal":      "다듬기: 준비됨(로컬)",
            "menu.polish.skipped":         "다듬기: 직전 처리를 건너뜀",
            "menu.polish.skippedTimeout":  "다듬기: 직전 처리가 시간 초과됨",
            "menu.polish.unavailable":     "다듬기: 사용할 수 없음",
            "menu.polish.breakerTripped":  "다듬기: 연속 실패로 비활성화됨",
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
            "alert.polishBreakerTitle": "다듬기 비활성화",
            "alert.polishBreakerBody":  "다듬기가 연속으로 세 번 실패하여 자동 비활성화되었습니다. 이번 녹음은 원문 그대로 붙여 넣어졌습니다. 설정에서 다시 켤 수 있습니다.",
            "settings.title":                  "다듬기 설정",
            "settings.polish.enable":          "받아쓰기 다듬기 사용",
            "settings.polish.description":     "군더더기와 말 더듬기를 정리합니다. 모든 처리는 Mac 안에서 이루어집니다.",
            "settings.polish.engine":          "엔진:",
            "settings.polish.system.label":    "시스템 내장 모델(Apple Intelligence)",
            "settings.polish.system.detail":   "다운로드 불필요·가장 빠름. 사용 가능할 때 권장.",
            "settings.polish.local.label":     "Scribe 로컬 모델(Gemma 4 E2B, 약 3.5 GB 다운로드)",
            "settings.polish.local.detail":    "모든 Apple Silicon Mac에서 동작합니다.",
            "settings.polish.statusPrefix":    "상태: ",
            "settings.polish.download":        "다운로드…",
            "settings.polish.done":            "완료",
            "polish.system.statusAvailable":         "사용 가능",
            "polish.system.statusDeviceNotEligible": "이 기기에서는 사용할 수 없음 — 현재 지역은 Apple Intelligence 미지원",
            "polish.system.statusNotEnabled":        "시스템 설정에서 Apple Intelligence를 켜 주세요",
            "polish.system.statusModelNotReady":     "Apple Intelligence 모델 준비 중 — 잠시 후 다시 시도해 주세요",
            "polish.system.statusUnavailable":       "사용할 수 없음",
            "polish.system.statusRequiresMacOS26":   "macOS 26(Tahoe) 이상이 필요합니다",
            "polish.local.statusReady":          "사용 가능",
            "polish.local.statusNotDownloaded":  "다운로드 안 됨 — '다운로드'를 눌러 모델 가져오기(약 1 GB)",
            "polish.local.statusDownloading":    "다운로드 중… %d%%",
            "polish.local.statusVerifying":      "SHA-256 확인 중…",
            "polish.local.statusFailed":         "다운로드 실패",
            "polish.local.statusLoadFailed":     "모델 로드 실패",
            "polish.local.failNetwork":          "다운로드 미러에 접속할 수 없습니다 — 네트워크를 확인하세요",
            "polish.local.failMirror":           "모든 미러가 오류를 반환했습니다",
            "polish.local.failIntegrity":       "해시 불일치 — 파일 거부됨",
            "polish.local.failNotPinned":       "이 빌드는 모델 해시가 고정되지 않았습니다",
            "polish.local.failDiskFull":        "디스크 공간 부족",
            "polish.local.failIO":              "I/O 오류",
            "settings.polish.cancel":            "취소",
            "settings.polish.delete":            "모델 파일 삭제",
            "settings.polish.mirror":            "미러:",
            "settings.polish.mirror.auto":       "자동",
        ],
    ]
}
