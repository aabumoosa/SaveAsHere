# Phase 0 Findings — Accessibility reachability

This document, not the README or the spec, is the source of truth for what actually
works. Every row is an observation, not an expectation.

Machine: macOS 26.6 (build 25G72), Apple Silicon. Recorded 2026-07-30.
Active keyboard layout during testing: **Arabic** — this turned out to matter, see §3.

---

## 1. Permission attribution

**Question:** which process does macOS attribute the Accessibility grant to when the
diagnostic runs as a command-line binary?

**Observed:** the grant follows the *responsible* process, not the binary.
`./.build/debug/SaveAsHere trust` reported `accessibility-trusted: true` with no prompt,
because the process chain is:

```
/bin/zsh  ->  claude  ->  -zsh  ->  login  ->  Terminal.app
```

and Terminal.app already holds the grant on this machine.

**Consequences:**

1. Recon needed no new permission prompt.
2. A `true` result during development says nothing about the shipped app.
   `SaveAsHere.app` launched from Finder is its own responsible process and needs its
   own grant. Task 11 must verify that separately.

## 2. Stable accessibility identifiers (TextEdit, non-sandboxed host)

Every element the agent needs is exposed with a **stable, non-localised
`AXIdentifier`** — considerably better than the role-and-heuristic matching the spec
originally assumed.

| Element | Identifier | Notes |
|---|---|---|
| Save panel | `save-panel` | An `AXSheet`, child of the document window. Not exposed via any `AXSheets` attribute; found by scanning children |
| Filename field | `saveAsNameTextField` | `AXValue` is the suggested name, e.g. `Sample` |
| Current folder | `where popup` | An `AXPopUpButton`; `AXValue` is the folder *name* only, e.g. `sample-docs` |
| Cancel | `CancelButton` | Enabled while the panel is open |
| Save | `OKButton` | **Disabled while the goto sheet is open** — see §4 |
| Goto sheet | `GoToWindow` | An `AXSheet`, child of the save panel |
| Goto path field | `PathTextField` | Writable; offers an `AXConfirm` action |
| Goto dismiss | `CloseButton` | Inside `GoToWindow` |

`AXDocument` on TextEdit's focused window is a `file://` URL:
`file:///Users/.../Scripts/recon/sample-docs/Sample.txt`. The generic
path-resolution route works.

## 3. The keyboard-layout trap

**Synthetic ⌘⇧G built from the virtual keycode alone does nothing under a non-Latin
keyboard layout.**

Discovered by posting `kVK_ANSI_X` to TextEdit and observing what the text area
received: **`ء`**, not `X`. macOS resolves key equivalents against the characters an
event carries, and under the Arabic layout the ANSI "G" key does not produce "g", so
"Go to folder" never matches.

**Fix, verified:** call `CGEvent.keyboardSetUnicodeString` to state the character
explicitly. With that added, `GoToWindow` appears reliably.

This would otherwise have shipped as an unreproducible "works on my machine" defect.
Any future keystroke work must keep the explicit Unicode string.

Also observed, unrelated but relevant to recon tooling:

- Menu items are **disabled while the application is not active**, so pressing one via
  Accessibility requires activating the app first.
- In TextEdit, **`Save As…` is ⌘⌥⇧S (modifier mask 3)**, while **⌘⇧S is `Duplicate`**
  (mask 1). Pressing the wrong one creates a document instead of opening a panel.
- Focus drifts back to the calling terminal between separate command invocations, so
  any tool that synthesises input must activate its target within the same process run.

## 4. Confirming the goto sheet — the blocking finding

**Question that decides the mechanism:** can the goto sheet be confirmed without
sending Return?

**Answer: no.** Four routes were tested against a live panel:

| Route | Result |
|---|---|
| Press `AXDefaultButton` on `GoToWindow` | Attribute is **advertised but empty**; no element returned |
| Find a Go button among the sheet's children | **No such element exists.** The sheet contains only a static text, `CloseButton`, `PathTextField`, and a path table |
| `AXConfirm` action on `PathTextField` | Returns `true`, **has no effect**; sheet stays open, folder unchanged |
| `AXOpen` on the path table's deepest row | Returns `true`, **has no effect**; folder unchanged |
| Settable attribute on `save-panel` to set the folder directly | **None.** Only `AXPosition`, `AXSections`, `AXSize` are settable |

Confirmed working parts of the sequence:

- ⌘⇧G opens `GoToWindow` (with the Unicode-string fix).
- Writing `PathTextField` via `AXValue` **succeeds and registers with the sheet's
  model** — the path table updated to `Users / Abumoosa / Desktop / SaveAsDialogh`.
- Read-back verification of the written path works.
- The filename field was **preserved in every trial**.
- Cleanup works: `CloseButton` dismisses the goto sheet, `CancelButton` dismisses the
  panel. **No save ever occurred.**

So the sequence is complete except for its final step, and only a Return keystroke
remains as a way to perform it.

### Safety context for that decision

The original invariant said Return must never be sent, because Return arriving at a
save panel presses its default button, which is Save. The evidence changes the risk
picture:

- While `GoToWindow` is open, the panel's `OKButton` (Save) is **disabled**. A Return
  that reached the panel in that state could not save.
- `GoToWindow` presence is verifiable via Accessibility immediately before sending.
- `OKButton`'s enabled state is also verifiable immediately before sending.

The residual risk is a race: the sheet closing between the final check and the
keystroke landing. The user is not interacting during this window (they invoked the
hotkey), so the window is sub-millisecond, but it is not zero.

**This is escalated to the user as a decision, per spec §7 — not resolved by
assumption.**

## 5. Sandboxed applications are reachable

**Question:** a sandboxed app does not host its own save panel — macOS runs the panel in
a separate service process. Can Accessibility traverse and drive it?

**Answer: yes.** Pages (sandboxed, App Store) exposes the panel with **exactly the same
identifiers** as non-sandboxed TextEdit: `save-panel`, `saveAsNameTextField`,
`where popup`, `CancelButton`, `OKButton`. The full sequence was performed against it
successfully, filename preserved, no save.

This was the largest unknown in the project and it resolves in the favourable direction.

**But Pages exposes no `AXDocument`.** The generic path route fails there, so the agent
correctly declines with `unknownDocumentFolder`. Pages needs a Phase 2 adapter
(`tell application "Pages" to get file of front document`).

## 6. The bidirectional-text trap

The panel reports its current folder **rendered for display**, not as a path component.
For a right-to-left name it wraps the text in Unicode bidirectional controls.

Observed in Pages, for the folder `ميزانية 2026`:

```
AXValue = U+200E U+2066 ميزانية 2026 U+2069
```

Those characters never appear in a filesystem path component. Comparing the two directly
means **every folder with a non-Latin name compares as different from itself**, with two
visible consequences: a successful move is misreported as `navigatedUnverified`, and the
"panel is already in the right folder" check never fires, so the agent re-navigates
pointlessly.

**Fix:** `FolderName.normalize` strips all twelve bidirectional formatting characters
before comparing. Verified against the real panel: moving into `ميزانية 2026` is now
reported as confirmed, and a second attempt correctly skips.

This matters disproportionately here because the user's folder names are frequently
Arabic. It is the kind of defect that would never surface on an English-only test system.

## 7. Application support

Swept 2026-07-31. Every application was driven from a document opened fresh from disk.

| Bundle ID | AXDocument | Save As mask | Notification | Panel opened at | Verdict |
|---|---|---|---|---|---|
| com.apple.TextEdit | Yes, `file://` URL | 3 | `AXSheetCreated` 171 ms | document's folder | **Works** — verified end to end |
| com.apple.Preview | Yes | 3 | `AXSheetCreated` 349 ms | document's folder | **Works** |
| com.microsoft.Word | Yes | 1 | `AXSheetCreated` 286 ms | document's folder | **Works** |
| com.microsoft.Excel | Yes | 1 | `AXSheetCreated` 243 ms | document's folder | **Works** |
| com.apple.dt.Xcode | Yes | 3 | `AXSheetCreated` 227 ms | document's folder | **Works** |
| com.microsoft.VSCode | Yes | 1 | `AXSheetCreated` 523 ms | document's folder | **Works** — but see §9 |
| com.apple.iWork.Numbers | **No** | 3 | `AXSheetCreated` 221 ms | **Downloads** | **Abstains** — `unknownDocumentFolder`. Needs Phase 2 |
| com.apple.iWork.Pages | **No** | 3 | not tested — no document open | | **Abstains** — needs Phase 2 |

**Save As is not ⌘⇧S everywhere.** Mask 3 (⌘⌥⇧S) in the Apple applications and Xcode,
where **mask 1 is `Duplicate`**; mask 1 (⌘⇧S) in Word, Excel and VS Code, where it is
Save As. Pressing the wrong one in an Apple application duplicates the document.

### The finding that reframes the value

**In seven of the eight, the panel already opened at the document's own folder**, so
the agent correctly reported `alreadyShowingFolder` and did nothing. The one
application whose panel opened elsewhere — Numbers, at `Downloads` — is also the one
publishing no `AXDocument`, so it is the one the agent cannot help.

This is a statement about these tests, not a verdict on the tool. Every document was
opened fresh from disk immediately beforehand, which is the case most likely to make
Save As default to the document's folder. Whether the panel drifts to a last-used
folder over a longer working session is **not** established here, and is the obvious
next thing to measure.

What it does establish is where the remaining value sits: **Phase 2, the Apple Events
path resolver.** Numbers shows the exact shape of the problem — panel in the wrong
place, document folder known to the application but not reachable through
accessibility.

Word and Excel report `AXDocument` as `file:///tmp/…` where the others report
`/private/tmp/…`. Both resolve, since `/tmp` is a symlink and the folder comparison
uses only the last path component. Recorded because a future path comparison could
trip on it.

## 8. Panel-appearance notifications — the automatic-mode finding

**Question that decides automatic mode:** does an application actually emit an
accessibility notification when its save panel appears, and is the panel usable at
that instant? The API existing says nothing about an application using it.

Measured with `probe-notifications --bundle com.apple.TextEdit`, which subscribes on
the **application** element and presses Save As itself.

| Observation | TextEdit |
|---|---|
| `AXSheetCreated` | **Arrives**, 171 ms after the menu press |
| `AXWindowCreated` | Never arrives — the panel is a sheet, not a window |
| `AXFocusedWindowChanged` | Arrives too, 503 ms, for the same element |
| Element carried | The panel itself, not an ancestor |
| `AXIdentifier` at that instant | Already `save-panel`. No wait needed to recognise it |
| Controls at that instant | `saveAsNameTextField`, `OKButton` and `where popup` all readable immediately |

Three consequences for the design:

1. **No readiness wait is needed.** The panel is fully usable when the notification
   fires, so the agent can act at once rather than polling for the controls.
2. **Subscribing on the application element is sufficient** — the sheet need not exist
   when the subscription is made.
3. **Two notifications arrive for one panel.** Acting on each would move the panel
   twice, so handling any panel only once is a requirement, not a precaution.

`AXWindowCreated` remains subscribed even though TextEdit never sends it: an
application with no document window may present the panel as a standalone window. Each
row of §7 records what that application actually emits.

Also worth noting for the remaining sweep: in both TextEdit and Pages, **`Save As…` is
⌘⌥⇧S (mask 3)** and **⌘⇧S is `Duplicate`** (mask 1). Any per-app work must not assume
⌘⇧S means Save As.

## 9. Attaching too early — the launch race

Found by testing, not by reasoning about the code.

The agent attaches its observer when an application becomes frontmost. For an
application that has *just launched*, accessibility is not ready at that moment:
`AXObserverCreate` and its subscriptions all fail, and the agent logged
`auto: no notification path for com.microsoft.VSCode`.

Measured contrast that isolates the cause: the `probe-notifications` command,
subscribing to the same VS Code process moments later, succeeded completely.
Re-activating VS Code after it had settled also succeeded. Nothing about VS Code
prevents observation — only the timing did.

The consequence was not small. The agent never retried, so a freshly launched
application had **no automatic mode for the rest of its session** — exactly when a
user is most likely to open a document and save it.

Fix: on failure the attach is retried twice, one second apart, and only while that
application is still frontmost and nothing else has claimed the watcher. Verified
afterwards against a cold launch of Xcode, which produced no failure line.

A failure line that survives the retries is still meaningful: it says that
application publishes no notification path, and only the hotkey will work there.

## 10. macOS 27 — the Return gate stopped holding

Machine: macOS 27.0 (build 26A428). Recorded 2026-09-22, after the user reported that
panels opened the goto sheet and then did nothing.

**Symptom.** Every run since the upgrade ended `failed: saveButtonNotDisabled`, and the
user was left looking at an open goto sheet with an **empty** field.

Two separate changes in macOS 27 caused it. Everything else — identifiers, structure,
writing the path, read-back — is unchanged from §2 and §4.

### 10.1 Save is no longer disabled while the goto sheet is open

Measured in TextEdit and in sandboxed Preview, goto sheet open:
`OKButton AXEnabled=1`. On 26.6 it was `0` (§4). Gate condition (b) could therefore
never pass, and the agent correctly refused to send Return every time.

The non-keystroke routes were re-tested on 27 and still do nothing: `AXConfirm` on
`PathTextField` and `AXOpen` on the path rows both return `true` and leave the folder
unchanged. Return remains the only confirmation.

**Replacement, approved by the user on 2026-09-22:** condition (b) is now *keyboard focus
is in the sheet's path field*, which is where a Return would land. It is read as:
the field's application is frontmost **and** that application's `AXFocusedUIElement`
is `CFEqual` to the field. Both halves are needed:

| Reading | TextEdit | Preview (sandboxed) | TextEdit behind Finder |
|---|---|---|---|
| Application `AXFocusedUIElement` = field | true | true | **true** |
| System-wide `AXFocusedUIElement` | empty | empty | — |
| Gate reading (frontmost + application focus) | true | true | **false** |

The last column is why the frontmost half exists: an application keeps its internal
focus while in the background, so application focus alone would pass while the
keystroke went to another application. The system-wide reading, which would have
answered both halves at once, returns nothing on 27 and is not used.

What was given up: on 26.6 a Return that reached the panel could not save, because
Save was disabled. On 27 it could. The remaining exposure is the sheet closing, or
focus moving, between the gate check and the keystroke — the same sub-millisecond
window as before, now without that second line of defence.

### 10.2 The close button clears before it closes

`CloseButton` in the goto sheet, pressed once while the field holds text, **empties the
field and leaves the sheet open**. A second press closes it. Measured:
first press `sheetPresent=true`, field empty; second press `sheetPresent=false`.

The agent's cleanup pressed once, which is exactly the state in the user's screenshot.
`dismiss()` now presses until the sheet is confirmed gone, at most three times.

### 10.3 Verified after the fix

`run-once` against TextEdit and Preview, each with a target folder different from the
one the panel showed: `moved to …` in about 820 ms, `where popup` showing the target,
filename unchanged, goto sheet gone, and no file written to the target folder.
`probe-close` on a sheet holding text: `dismiss() confirmed closed: true`.

Automatic mode on 27, from the user's own use after the fix was installed:
`auto: moved to Desktop` (886 ms) and `auto: moved to Downloads` (854 ms).

### 10.4 Running diagnostics without a Terminal grant

The Claude desktop app is not in the Accessibility list, so `./.build/debug/SaveAsHere`
reports `trusted=false` from there — §1's inheritance no longer applies. Launching the
signed bundle through LaunchServices makes it its own responsible process, and it
inherits the bundle's grant:

```bash
open -n -a build/SaveAsHere.app --stdout out.txt --stderr err.txt --args <command> ...
```
