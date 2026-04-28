import Foundation
import ScribeCore

struct EvalCase {
    enum Kind { case repair, keep, disfluency }
    let kind: Kind
    let raw: String
    let mustContain: [String]
    let mustNotContain: [String]
    let note: String
}

let cases: [EvalCase] = [
    // ---------- repair: ASR transliteration → English term ----------
    EvalCase(
        kind: .repair,
        raw: "我刚刚在给他上面提了一个 PR 帮我看一下",
        mustContain: ["GitHub"],
        mustNotContain: ["给他上"],
        note: "GitHub mistranscribed as 给他"
    ),
    EvalCase(
        kind: .repair,
        raw: "你帮我把这个功能 普世 到 给他 上",
        mustContain: ["push", "GitHub"],
        mustNotContain: ["普世"],
        note: "push + GitHub double-mistranscription"
    ),
    EvalCase(
        kind: .repair,
        raw: "明天早上 给特扒 之后我们去吃早饭",
        mustContain: ["get up"],
        mustNotContain: ["给特扒"],
        note: "get up mistranscribed (no nearby tech context)"
    ),
    EvalCase(
        kind: .repair,
        raw: "这个项目是用 派森 写的 跑在 阿派艾 网关后面",
        mustContain: ["Python", "API"],
        mustNotContain: ["派森", "阿派艾"],
        note: "Python + API mistranscriptions"
    ),
    EvalCase(
        kind: .repair,
        raw: "记得更新一下 瑞德米",
        mustContain: ["README"],
        mustNotContain: ["瑞德米"],
        note: "README mistranscribed"
    ),
    EvalCase(
        kind: .repair,
        raw: "我用 克劳德口德 写了个脚本",
        mustContain: ["Claude Code"],
        mustNotContain: ["克劳德口德", "克劳德口的"],
        note: "Claude Code mistranscribed"
    ),
    EvalCase(
        kind: .repair,
        raw: "他把这段话 缘分不动 地搬过去了",
        mustContain: ["原封不动"],
        mustNotContain: ["缘分不动"],
        note: "Chinese homophone typo"
    ),

    // ---------- keep: literal reading is correct, do NOT over-correct ----------
    EvalCase(
        kind: .keep,
        raw: "晚上你给他打个电话问一下情况",
        mustContain: ["给他"],
        mustNotContain: ["GitHub"],
        note: "literal pronoun+verb — must NOT become GitHub"
    ),
    EvalCase(
        kind: .keep,
        raw: "我准备给他买杯咖啡",
        mustContain: ["给他"],
        mustNotContain: ["GitHub"],
        note: "literal — give him coffee"
    ),
    EvalCase(
        kind: .keep,
        raw: "我刚刚在 GitHub 上提了一个 PR",
        mustContain: ["GitHub", "PR"],
        mustNotContain: ["代码托管", "应用程序"],
        note: "already-correct English token must survive"
    ),
    EvalCase(
        kind: .keep,
        raw: "今天下午三点开会会议室是 B201",
        mustContain: ["B201"],
        mustNotContain: [],
        note: "no ASR errors — pure punctuation cleanup"
    ),

    // ---------- disfluency: just clean fillers, no repair needed ----------
    EvalCase(
        kind: .disfluency,
        raw: "嗯那个我我觉得我们应该应该把这个 feature 在周二上线吧",
        mustContain: ["feature"],
        mustNotContain: ["嗯", "那个"],
        note: "filler removal + dedup, English token preserved"
    ),
]

@MainActor
func runEval() async {
    print("=== Polish Eval ===")
    print("Loading model …")
    guard PolishEvalAPI.isReady else {
        print("ERROR: model not ready: \(PolishEvalAPI.statusText)")
        exit(1)
    }

    // First call warms up the context. Subsequent calls reuse it.
    do {
        _ = try await PolishEvalAPI.runOnce(raw: "测试", languageHint: "Simplified Chinese")
    } catch {
        print("ERROR: warmUp via first call failed: \(error)")
        exit(1)
    }
    print("Model loaded.\n")

    let runsPerCase = 3
    var totalPasses = 0
    var totalRuns = 0
    var perKindPasses: [EvalCase.Kind: (pass: Int, total: Int)] = [:]

    for (idx, c) in cases.enumerated() {
        var caseRuns: [(passed: Bool, output: String)] = []
        for _ in 0..<runsPerCase {
            let out: String
            do {
                out = try await PolishEvalAPI.runOnce(
                    raw: c.raw,
                    languageHint: "Simplified Chinese"
                )
            } catch {
                out = "<ERROR: \(error)>"
            }
            let containsAll = c.mustContain.allSatisfy { out.contains($0) }
            let containsNone = c.mustNotContain.allSatisfy { !out.contains($0) }
            let passed = containsAll && containsNone
            caseRuns.append((passed, out))
        }

        let passCount = caseRuns.filter { $0.passed }.count
        totalPasses += passCount
        totalRuns += runsPerCase
        var kindStats = perKindPasses[c.kind] ?? (0, 0)
        kindStats.pass += passCount
        kindStats.total += runsPerCase
        perKindPasses[c.kind] = kindStats

        let kindLabel: String
        switch c.kind {
        case .repair:     kindLabel = "REPAIR"
        case .keep:       kindLabel = "KEEP"
        case .disfluency: kindLabel = "DISF"
        }
        print("[#\(idx + 1) \(kindLabel)] \(c.note)")
        print("  raw: \(c.raw)")
        for (i, r) in caseRuns.enumerated() {
            let mark = r.passed ? "✓" : "✗"
            let oneLine = r.output.replacingOccurrences(of: "\n", with: " ⏎ ")
            print("  out#\(i + 1) \(mark): \(oneLine)")
        }
        print("  ⇒ \(passCount)/\(runsPerCase)\n")
    }

    print("=== Summary ===")
    for kind in [EvalCase.Kind.repair, .keep, .disfluency] {
        if let s = perKindPasses[kind] {
            let label: String
            switch kind {
            case .repair:     label = "REPAIR"
            case .keep:       label = "KEEP"
            case .disfluency: label = "DISFLUENCY"
            }
            let pct = Double(s.pass) / Double(s.total) * 100
            print(String(format: "  %@: %d/%d (%.0f%%)", label, s.pass, s.total, pct))
        }
    }
    let pct = Double(totalPasses) / Double(totalRuns) * 100
    print(String(format: "  TOTAL: %d/%d (%.0f%%)", totalPasses, totalRuns, pct))
}

Task { @MainActor in
    await runEval()
    exit(0)
}
RunLoop.main.run()
