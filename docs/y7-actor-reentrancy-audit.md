# Y7 — Actor reentrancy audit (Polish pipeline)

> **Outcome:** the existing snapshot pattern in `PolishCoordinator.maybePolish`
> plus the `.polishing` state lock in `AppDelegate` covers every load-bearing
> reentrancy path. **No code change required.** Documenting the analysis so
> future changes don't reintroduce a hazard.

## Premise

`PolishCoordinator.maybePolish` is `@MainActor`, and inside it we `await
svc.polish(...)`. While that `await` is suspended, the main actor is free —
any other `@MainActor` work (NSApplication notifications, menu actions, the
Settings UI) can interleave with the in-flight polish. The Y7 audit asks
whether any of those interleavings can corrupt the result.

## Inventory

For each mutable property reachable from the polish path, the question is:
*can this change while `svc.polish(...)` is awaiting, and if so, does it
matter?*

### `PolishCoordinator`

| Property | Mutator | Mid-await change? | Effect on in-flight polish |
|---|---|---|---|
| `system`, `local` | `init`, `injectStubService` (test only) | No in production | — |
| `isAdaptiveEnabled` | Settings toggle | Yes | **Snapshot taken** at call entry: `systemPrompt` was assembled before the await; the in-flight call carries its own copy. |
| `mirrorPreference` | Settings dropdown | Yes | Affects future downloads only; not read mid-polish. |
| `isEnabled` | Settings toggle, breaker | Yes | The current call already passed the `guard let svc = active()` check. Continuing is benign — pasting a polished result for a call that the user just disabled is at most a minor UX surprise. |
| `selectedBackend` | Settings radio | Yes | Resolved at call entry to `svc`; mid-await change has no effect. |
| `consecutiveFailures`, `lastFailureMessage`, `isBreakerTripped`, `consecutiveTimeouts`, `lastCallTimedOut` | `recordSuccess` / `recordFailure` / `recordTimeout` (this same call site after the await) | Yes — but only by **this same call**, after the await returns | Single-writer; reentry is blocked (see below). |
| `polishTask` | `AppDelegate` (not coordinator) | — | — |

### `LocalPolishService`

| Property | Mutator | Mid-await change? | Effect on in-flight polish |
|---|---|---|---|
| `downloadState` | downloader callbacks, `purgeModel`, `refreshAvailability` | Yes | Read by `isReady` / `statusText` for UI. The polish call captured `ctx` already (see below). |
| `context: LlamaContext?` | `polish` (assigned), `purgeModel`, `releaseContextForShutdown` | Yes | **Snapshot taken**: `polish` does `guard let ctx = context else { ... }` then calls `ctx.generate(...)`. The local `ctx` retains the `LlamaContext` instance even if `self.context = nil` happens mid-await. Plus the inference queue's `[self]` capture in `LlamaContext.generate` keeps the C resources alive until generation returns. R2's `cancelAndDrain` is the explicit shutdown path. |
| `contextWarmedUp: Bool` | `warmUp`, `purgeModel`, `releaseContextForShutdown` | Yes | Read in `warmUp` (idempotent). Mid-warmUp toggling could in theory flag a not-yet-warmed context as warmed, but warmUp is called per-polish under the `.polishing` state lock — no concurrent warmUp in production. |

### `SystemPolishService`

| Property | Mutator | Mid-await change? | Effect on in-flight polish |
|---|---|---|---|
| `isReady`, `statusText` | `refreshAvailability` | Yes | Read by `active()` at coordinator entry; snapshotted via `let svc = active()`. Refresh during `await` doesn't affect the in-flight result. |
| `session: Any?`, `sessionPromptKey: String?` | `polish` itself, `buildSession` | Yes within this call | Rebuilt only when the prompt-cache key mismatches (Y6 hardened the key; collision risk eliminated). Reentry would have seen the same session, but reentry is blocked. |

### `PersonaStore`

| Property | Mutator | Mid-await change? | Effect on in-flight polish |
|---|---|---|---|
| `persona: String` | `setPersona` (Settings textarea) | Yes | The system prompt was assembled at call entry with the *old* persona. The in-flight call uses its snapshot. |
| `recent: [Entry]` | `recordFinalText` (post-polish), `purgeAll` (Reset button, G11) | `purgeAll` yes | Post-polish `recordFinalText` runs after the await returns, so no conflict with the in-flight polish itself. `purgeAll` mid-await is benign — the just-written entry from the post-await `recordFinalText` would be the only entry afterward, but that's the user's intent (they hit Reset). |

## The single load-bearing guarantee

The audit only holds because **`AppDelegate`'s `.polishing` state rejects new
`fnDown` events** ([Sources/Scribe/AppDelegate.swift:151](../Sources/Scribe/AppDelegate.swift#L151)):

```swift
guard isEnabled, case .idle = sessionState else { return }
```

Without that lock, a user re-pressing Fn could trigger a second
`maybePolish` while the first is awaiting. That second call would see the
breaker counter mid-update, the persona possibly mid-edit, and would issue
a second `ctx.generate` on the same `LlamaContext` (whose inference queue
is serial — so it would block, but the awaiting Task ordering would be
hard to reason about).

This guarantee is documented in CLAUDE.md ("**`.polishing` locks Fn out**")
and is part of why the state machine has five states rather than four.
**Do not collapse `.polishing` into `.idle` or weaken its `fnDown` guard.**
If the polish lifecycle ever needs to support concurrent calls, the audit
above changes shape — most prominently, `LlamaContext.cancelAndDrain` and
the per-call session rebuild logic in `SystemPolishService.polish` would
need explicit serialization.

## Why dropping `@MainActor` from `PolishService.polish` doesn't help

The original code-review draft floated removing `@MainActor` from the
protocol. After this audit it's clear that doesn't move the needle:

- The hazard isn't "blocking main"; it's reentrancy. `@MainActor` doesn't
  cause the await to release the actor — it just declares the call site
  conventions.
- Implementations would still touch `@MainActor` state internally
  (`statusText`, `downloadState` for the local backend; the FM session for
  the system backend). Moving the protocol off-actor just pushes the
  isolation declaration into the implementation.
- The actual fix for reentrancy hazards is the snapshot pattern in
  `maybePolish` plus the `.polishing` lock — which we already have.

## What would change this

If any of these hold in the future, redo the audit:

- **Concurrent polishes get enabled.** Removing the `.polishing` Fn lock,
  or adding a "queue multiple recordings" feature, breaks the single-writer
  invariant on the breaker counters and the Local backend's `context`
  property.
- **Persona becomes auto-derived mid-session.** Phase 5.2's plan (in
  [docs/adaptive-polish.md](adaptive-polish.md)) involves the model itself
  proposing persona updates. If those land *during* a polish call rather
  than *after*, the snapshot at call entry stops being conservative.
- **The system prompt grows runtime-context fields** (Phase 5.3 — the
  current-app tone). If the runtime context can change between assembly and
  polish completion, the snapshot guarantee weakens.
