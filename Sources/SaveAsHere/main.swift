import AppKit
import Carbon.HIToolbox
import CoreGraphics
import AXKit
import SaveAsCore

let arguments = Array(CommandLine.arguments.dropFirst())

/// Resolves the application to inspect.
///
/// Recon must be able to name its target explicitly: relying on "whichever app
/// is frontmost" produced a dump of the wrong application during Task 3, because
/// `open -b` does not reliably move focus.
func targetApplication() -> NSRunningApplication? {
    if let index = arguments.firstIndex(of: "--bundle"),
       arguments.count > index + 1 {
        let wanted = arguments[index + 1]
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: wanted)
            .first
    }
    return NSWorkspace.shared.frontmostApplication
}

/// Brings an application to the front and waits for the change to take effect.
///
/// Necessary because focus drifts back to the calling terminal between separate
/// invocations, and a synthesised keystroke goes to whichever application is
/// frontmost at that instant — not to the one we named.
@discardableResult
func activateAndWait(_ app: NSRunningApplication, timeout: TimeInterval = 2.0) -> Bool {
    app.activate()
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app.bundleIdentifier {
            return true
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app.bundleIdentifier
}

func requireTrustAndApp() -> NSRunningApplication {
    guard AXTrust.isTrusted(prompt: false) else {
        FileHandle.standardError.write(Data("error: not trusted\n".utf8))
        exit(1)
    }
    guard let app = targetApplication() else {
        FileHandle.standardError.write(Data("error: target application not running\n".utf8))
        exit(1)
    }
    return app
}

switch arguments.first {
case "trust":
    let trusted = AXTrust.isTrusted(prompt: arguments.contains("--prompt"))
    print("accessibility-trusted: \(trusted)")
    print("pid: \(ProcessInfo.processInfo.processIdentifier)")
    print("executable: \(ProcessInfo.processInfo.arguments[0])")
    exit(trusted ? 0 : 1)

case "dump":
    let app = requireTrustAndApp()
    print("# app: \(app.localizedName ?? "?") bundle: \(app.bundleIdentifier ?? "?")")
    let root = AXElement.application(pid: app.processIdentifier)
    print(AXTreeDumper.dump(root, maxDepth: 12))

case "document":
    let app = requireTrustAndApp()
    let appElement = AXElement.application(pid: app.processIdentifier)
    let focused = appElement.element(kAXFocusedWindowAttribute)
    print("app: \(app.bundleIdentifier ?? "?")")
    print("AXDocument: \(focused?.string("AXDocument") ?? "<none>")")
    print("AXTitle: \(focused?.title ?? "<none>")")

case "probe-hotkey":
    // Reconnaissance only, and deliberately not part of AXKeystroke: synthesises
    // the agent's own hotkey so the running agent can be tested end to end.
    // Also answers whether Carbon hotkey matching survives a non-Latin keyboard
    // layout — it matches by keycode, unlike the character-based matching that
    // broke ⌘⇧G.
    let source = CGEventSource(stateID: CGEventSourceStateID.privateState)
    let key = CGKeyCode(kVK_ANSI_F)
    let mods: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    else { print("could not create event"); exit(1) }
    down.flags = mods
    up.flags = mods
    down.post(tap: CGEventTapLocation.cghidEventTap)
    up.post(tap: CGEventTapLocation.cghidEventTap)
    print("posted ⌃⌥⌘F")

case "probe-char":
    // Reconnaissance only, and deliberately separate from AXKeystroke: this
    // answers whether synthetic key events reach another application at all on
    // this OS version. It is not part of the agent's code path.
    let app = requireTrustAndApp()
    guard activateAndWait(app) else { print("not frontmost"); exit(1) }
    let source = CGEventSource(stateID: CGEventSourceStateID.privateState)
    let key = CGKeyCode(kVK_ANSI_X)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    else { print("could not create event"); exit(1) }
    down.post(tap: CGEventTapLocation.cghidEventTap)
    up.post(tap: CGEventTapLocation.cghidEventTap)
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.8))
    let appEl = AXElement.application(pid: app.processIdentifier)
    let focusedEl = appEl.element(kAXFocusedUIElementAttribute)
    print("focused role: \(focusedEl?.role ?? "?")")
    print("focused value: \(focusedEl?.string(kAXValueAttribute) ?? "<none>")")

case "probe-goto":
    // Reconnaissance only: sends the single Command-Shift-G keystroke to an
    // already-open save panel and reports what appeared. Presses nothing.
    let app = requireTrustAndApp()
    guard activateAndWait(app) else {
        print("could not bring target frontmost; the keystroke would go elsewhere")
        exit(1)
    }
    let variant = arguments.firstIndex(of: "--variant")
        .flatMap { arguments.count > $0 + 1 ? arguments[$0 + 1] : nil } ?? "private"
    let delivery: AXKeystroke.Delivery
    switch variant {
    case "hid":     delivery = .hidTap
    case "pid":     delivery = .toProcess(app.processIdentifier)
    default:        delivery = .privateSourceTap
    }
    print("delivery: \(variant)")
    AXKeystroke.commandShiftG(via: delivery)
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(1.2))
    let root = AXElement.application(pid: app.processIdentifier)
    print(AXTreeDumper.dump(root, maxDepth: 16))

case "run-once":
    // Runs the exact production path once against an already-open save panel,
    // so the real mechanism can be verified without the background agent.
    let app = requireTrustAndApp()
    guard activateAndWait(app) else { print("could not activate target"); exit(1) }
    let action = SaveAsAction(
        tracker: DocumentTracker(),
        navigator: PanelNavigator(
            waiter: RunLoopWaiter(),
            trace: { label, seconds in
                print(String(format: "  %@: %.0fms", label, seconds * 1000))
            }
        ),
        probe: RealFileSystemProbe()
    )
    let override = arguments.firstIndex(of: "--to")
        .flatMap { arguments.count > $0 + 1 ? arguments[$0 + 1] : nil }
        .map { URL(fileURLWithPath: $0) }
    let result = action.perform(on: app, overrideFolder: override)
    print(result.description)
    switch result {
    case .outcome(.navigated, _, _), .outcome(.navigatedUnverified, _, _):
        exit(0)
    default:
        exit(1)
    }

case "cancel-panel":
    // Reconnaissance cleanup: dismisses any goto sheet and then the save panel,
    // pressing only Close and Cancel. Never touches OKButton.
    let app = requireTrustAndApp()
    let root = AXElement.application(pid: app.processIdentifier)
    func findID(_ id: String, in element: AXElement, depth: Int = 0) -> AXElement? {
        if element.identifier == id { return element }
        guard depth < 16 else { return nil }
        for child in element.children {
            if let hit = findID(id, in: child, depth: depth + 1) { return hit }
        }
        return nil
    }
    if let sheet = findID("GoToWindow", in: root),
       let close = findID("CloseButton", in: sheet) {
        print("closed goto sheet: \(close.perform(kAXPressAction))")
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.3))
    }
    if let panel = findID("save-panel", in: root),
       let cancel = findID("CancelButton", in: panel) {
        print("cancelled save panel: \(cancel.perform(kAXPressAction))")
    } else {
        print("no save panel open")
    }

case "probe-close":
    // Reconnaissance: with a goto sheet already open, reports where keyboard focus
    // sits, then dismisses the sheet through the production path and reports
    // whether it actually closed. Asked because on macOS 27 a failed run left the
    // sheet open with its field emptied. Never touches the save panel's buttons.
    let app = requireTrustAndApp()
    let root = AXElement.application(pid: app.processIdentifier)
    guard let panel = SavePanelLocator.findSavePanel(inAppWithPID: app.processIdentifier),
          let sheet = SavePanelLocator.firstDescendant(
            withIdentifier: SavePanelLocator.ID.gotoSheet, in: panel, maxDepth: 1),
          let field = SavePanelLocator.firstDescendant(
            withIdentifier: SavePanelLocator.ID.gotoPathField, in: sheet, maxDepth: 2)
    else { print("FAIL: open a save panel and its goto sheet first"); exit(1) }
    let goto = AXGotoSheet(panel: panel, sheet: sheet, field: field)
    print("gate reading isPathFieldFocused=\(goto.isPathFieldFocused.map(String.init) ?? "<nil>")")
    // Three readings of "where will a keystroke land", compared because a
    // sandboxed app's panel lives in a separate service process and the readings
    // may disagree there.
    let focused = root.element(kAXFocusedUIElementAttribute)
    print("app focused: id=\(focused?.identifier ?? "<nil>") isPathField=\(focused.map { CFEqual($0.raw, field.raw) } ?? false)")
    let systemFocused = AXElement(AXUIElementCreateSystemWide()).element(kAXFocusedUIElementAttribute)
    var systemPID: pid_t = 0
    if let systemFocused { AXUIElementGetPid(systemFocused.raw, &systemPID) }
    var fieldPID: pid_t = 0
    AXUIElementGetPid(field.raw, &fieldPID)
    print("system focused: id=\(systemFocused?.identifier ?? "<nil>") pid=\(systemPID) isPathField=\(systemFocused.map { CFEqual($0.raw, field.raw) } ?? false)")
    print("field: AXFocused=\(field.bool(kAXFocusedAttribute).map(String.init) ?? "<nil>") pid=\(fieldPID) appPid=\(app.processIdentifier)")
    print("before: fieldValue=\(field.string(kAXValueAttribute) ?? "<nil>")")
    print("dismiss() confirmed closed: \(goto.dismiss())")
    print("after: sheetPresent=\(goto.isPresent)")

case "probe-settable":
    // Reconnaissance: is there a settable attribute that would let us set the
    // panel's folder directly, making any keystroke unnecessary?
    let app = requireTrustAndApp()
    let root = AXElement.application(pid: app.processIdentifier)
    func find(_ id: String, in element: AXElement, depth: Int = 0) -> AXElement? {
        if element.identifier == id { return element }
        guard depth < 16 else { return nil }
        for child in element.children {
            if let hit = find(id, in: child, depth: depth + 1) { return hit }
        }
        return nil
    }
    guard let panel = find("save-panel", in: root) else {
        print("no save-panel open"); exit(1)
    }
    print("save-panel attributes (settable marked *):")
    for name in panel.attributeNames().sorted() {
        print("  \(panel.isSettable(name) ? "*" : " ") \(name)")
    }
    print("save-panel actions: \(panel.actionNames())")

case "probe-navigate":
    // Reconnaissance: performs the exact sequence the agent will perform, on a
    // panel that is already open, and reports every step. Presses only the goto
    // sheet's Go or Cancel button — never the save panel's default button.
    let app = requireTrustAndApp()
    guard let target = arguments.firstIndex(of: "--to")
        .flatMap({ arguments.count > $0 + 1 ? arguments[$0 + 1] : nil }) else {
        print("usage: probe-navigate --bundle <id> --to <folder>")
        exit(2)
    }
    guard activateAndWait(app) else { print("could not activate"); exit(1) }

    let root = AXElement.application(pid: app.processIdentifier)

    func findByIdentifier(_ id: String, in element: AXElement, depth: Int = 0) -> AXElement? {
        if element.identifier == id { return element }
        guard depth < 16 else { return nil }
        for child in element.children {
            if let hit = findByIdentifier(id, in: child, depth: depth + 1) { return hit }
        }
        return nil
    }
    func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(seconds))
    }

    guard let panel = findByIdentifier("save-panel", in: root) else {
        print("FAIL: no save-panel found — open a Save As panel first")
        exit(1)
    }
    let nameField = findByIdentifier("saveAsNameTextField", in: panel)
    let wherePopup = findByIdentifier("where popup", in: panel)
    let originalName = nameField?.string(kAXValueAttribute)
    print("panel found. filename=\(originalName ?? "<nil>") where=\(wherePopup?.string(kAXValueAttribute) ?? "<nil>")")

    AXKeystroke.commandShiftG()
    var goto: AXElement?
    for _ in 0..<24 {
        wait(0.025)
        if let found = findByIdentifier("GoToWindow", in: panel) { goto = found; break }
    }
    guard let goto else { print("FAIL: GoToWindow never appeared"); exit(1) }
    print("goto sheet appeared")

    guard let pathField = findByIdentifier("PathTextField", in: goto) else {
        print("FAIL: no PathTextField"); exit(1)
    }
    let wrote = pathField.setValue(target, forAttribute: kAXValueAttribute)
    let readBack = pathField.string(kAXValueAttribute)
    print("write=\(wrote) readBack=\(readBack ?? "<nil>") matches=\(readBack == target)")
    guard wrote, readBack == target else {
        if let cancel = goto.element(kAXCancelButtonAttribute) {
            print("cancelling goto sheet: \(cancel.perform(kAXPressAction))")
        }
        exit(1)
    }

    // The goto sheet advertises AXDefaultButton but leaves it empty, and contains
    // no Go button element at all — only a text field, a close button and a path
    // table. Confirmation therefore goes through the text field's AXConfirm
    // action, which is delivered to that element and so cannot reach the save
    // panel's default button.
    let confirmed_press: Bool
    if let go = goto.element(kAXDefaultButtonAttribute) {
        confirmed_press = go.perform(kAXPressAction)
        print("pressed goto default button: \(confirmed_press)")
    } else if pathField.actionNames().contains("AXConfirm") {
        confirmed_press = pathField.perform("AXConfirm")
        print("performed AXConfirm on path field: \(confirmed_press)")
    } else {
        print("FAIL: no way to confirm the goto sheet")
        if let close = findByIdentifier("CloseButton", in: goto) {
            _ = close.perform(kAXPressAction)
        }
        exit(1)
    }

    let expected = (target as NSString).lastPathComponent
    var confirmed = false
    for _ in 0..<32 {
        wait(0.025)
        if wherePopup?.string(kAXValueAttribute) == expected { confirmed = true; break }
    }

    // If confirming the field did nothing, try the sheet's path table: its rows
    // expose an AXOpen action. This is the last non-keystroke route available.
    if !confirmed, findByIdentifier("GoToWindow", in: panel) != nil {
        print("AXConfirm did not navigate; trying AXOpen on path-table rows")
        var openable: [AXElement] = []
        func collectOpenable(_ element: AXElement, depth: Int = 0) {
            if element.actionNames().contains("AXOpen") { openable.append(element) }
            guard depth < 10 else { return }
            for child in element.children { collectOpenable(child, depth: depth + 1) }
        }
        collectOpenable(goto)
        print("openable rows: \(openable.compactMap { $0.string(kAXValueAttribute) })")
        if let last = openable.last {
            print("AXOpen on '\(last.string(kAXValueAttribute) ?? "?")': \(last.perform("AXOpen"))")
            for _ in 0..<32 {
                wait(0.025)
                if wherePopup?.string(kAXValueAttribute) == expected { confirmed = true; break }
            }
        }
    }
    let finalName = findByIdentifier("saveAsNameTextField", in: panel)?.string(kAXValueAttribute)
    print("folderConfirmed=\(confirmed) where=\(wherePopup?.string(kAXValueAttribute) ?? "<nil>")")
    print("filenamePreserved=\(finalName == originalName) value=\(finalName ?? "<nil>")")

    // Leave no state behind, and never press the panel's OKButton (Save).
    if let stale = findByIdentifier("GoToWindow", in: panel),
       let close = findByIdentifier("CloseButton", in: stale) {
        print("closed goto sheet: \(close.perform(kAXPressAction))")
        wait(0.3)
    }
    if let cancel = findByIdentifier("CancelButton", in: panel) {
        print("cancelled save panel: \(cancel.perform(kAXPressAction))")
    }

case "dump-menu":
    // Reconnaissance only: the menu bar is not part of the application element's
    // AXChildren, so `dump` never reaches it.
    let app = requireTrustAndApp()
    let appElement = AXElement.application(pid: app.processIdentifier)
    print("app attributes: \(appElement.attributeNames().sorted().joined(separator: ", "))")
    guard let menuBar = appElement.element("AXMenuBar") else {
        print("no AXMenuBar attribute")
        exit(1)
    }
    for barItem in menuBar.children {
        print("MENU: \(barItem.title ?? "?")")
        for menu in barItem.children {
            for item in menu.children {
                let char = item.string("AXMenuItemCmdChar") ?? ""
                let mask = item.attribute("AXMenuItemCmdModifiers") as? Int
                let enabled = item.bool(kAXEnabledAttribute) ?? true
                print("  - \(item.title ?? "<separator>")"
                      + (char.isEmpty ? "" : "  [key=\(char) mods=\(mask.map(String.init) ?? "?")]")
                      + (enabled ? "" : "  (disabled)"))
            }
        }
    }

case "trigger-save-as":
    // Reconnaissance only: opens a save panel by pressing a menu item identified
    // by its key equivalent. Never confirms a save.
    //
    // The modifier mask is a parameter because it is not consistent across
    // applications. In TextEdit, Save As… is Command-Option-Shift-S (mask 3)
    // while Command-Shift-S (mask 1) is Duplicate — pressing the wrong one
    // creates a document instead of opening a panel.
    let app = requireTrustAndApp()

    // Menu items are disabled while the application is not active, so pressing
    // one requires activating it first.
    app.activate()
    var attempts = 0
    while !(NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            == app.bundleIdentifier), attempts < 40 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        attempts += 1
    }
    let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
    print("frontmost: \(frontmost)")

    // Only mask 3 (Command-Option-Shift-S) by default. There is deliberately no
    // fallback to mask 1: that is Duplicate in both TextEdit and Pages, and when
    // Save As is disabled — as it is whenever a panel is already open — falling
    // back silently created an untitled duplicate document. Failing is better.
    let requested = arguments.firstIndex(of: "--mods")
        .flatMap { arguments.count > $0 + 1 ? Int(arguments[$0 + 1]) : nil }
    let masks = [requested
        ?? (AXMenuSearch.CmdModifiers.shift | AXMenuSearch.CmdModifiers.option)]

    var pressed = false
    for mask in masks {
        guard let item = AXMenuSearch.findItem(
            cmdChar: "S", modifiers: mask, inAppWithPID: app.processIdentifier
        ) else { continue }
        let enabled = item.bool(kAXEnabledAttribute) ?? true
        print("candidate: \(item.title ?? "<untitled>") mods=\(mask) enabled=\(enabled)")
        guard enabled else { continue }
        print("pressed: \(item.perform(kAXPressAction))")
        pressed = true
        break
    }
    if !pressed {
        print("no enabled save-panel menu item found")
        exit(1)
    }

case "probe-notifications":
    // Reconnaissance, and the gating question for automatic mode: does an
    // application actually emit a notification when its save panel appears, what
    // element does that notification carry, and is the panel usable at that
    // instant? The API existing says nothing about an application using it.
    //
    // Listens only. The panel it opens is dismissed with Cancel; OKButton is never
    // touched.
    let app = requireTrustAndApp()
    guard activateAndWait(app) else { print("could not activate target"); exit(1) }
    let pid = app.processIdentifier
    let listenFor = arguments.firstIndex(of: "--seconds")
        .flatMap { arguments.count > $0 + 1 ? TimeInterval(arguments[$0 + 1]) : nil } ?? 6.0

    var arrived: [String] = []
    var triggeredAt = Date()

    /// Reports whether the controls the agent needs are readable right now.
    func describeControls(of panel: AXElement, _ label: String) {
        let controls = SavePanelLocator.collect(
            [SavePanelLocator.ID.filenameField,
             SavePanelLocator.ID.saveButton,
             SavePanelLocator.ID.wherePopup],
            in: panel, maxDepth: SavePanelLocator.controlDepth)
        let filename = controls[SavePanelLocator.ID.filenameField]?.string(kAXValueAttribute)
        let saveEnabled = controls[SavePanelLocator.ID.saveButton]?.bool(kAXEnabledAttribute)
        let folder = controls[SavePanelLocator.ID.wherePopup]?.string(kAXValueAttribute)
        print("    \(label): filename=\(filename ?? "<unreadable>")"
              + "  saveEnabled=\(saveEnabled.map(String.init(describing:)) ?? "<unreadable>")"
              + "  where=\(folder ?? "<unreadable>")")
    }

    guard let watcher = AXObserverBox(pid: pid, handler: { notification, element in
        arrived.append(notification)
        print(String(format: "[%6.0fms] %@", Date().timeIntervalSince(triggeredAt) * 1000,
                     notification))
        print("    role=\(element.role ?? "?")  subrole=\(element.subrole ?? "?")"
              + "  identifier=\(element.identifier ?? "<nil>")")

        // Is the panel identifiable from what the notification carries, without
        // waiting? That is what decides whether the agent can act immediately.
        if element.identifier == SavePanelLocator.ID.panel {
            print("    carries the save panel itself")
            describeControls(of: element, "at notification")
        } else if let nested = SavePanelLocator.firstDescendant(
            withIdentifier: SavePanelLocator.ID.panel, in: element, maxDepth: 3) {
            print("    save panel nested inside this element")
            describeControls(of: nested, "at notification")
        }
    }) else {
        print("AXObserverCreate failed — no notification path exists for this process")
        exit(1)
    }

    for notification in [kAXSheetCreatedNotification,
                         kAXWindowCreatedNotification,
                         kAXFocusedWindowChangedNotification] {
        print("subscribe \(notification): \(watcher.subscribe(notification))")
    }
    watcher.start()

    if arguments.contains("--no-trigger") {
        print("listening for \(Int(listenFor))s — open a save panel by hand")
        triggeredAt = Date()
    } else {
        // Not every application uses ⌘⌥⇧S: it is Save As in TextEdit, Pages,
        // Preview and Numbers, but ⌘⇧S elsewhere. Passing the wrong mask presses
        // Duplicate in the Apple applications, so there is no fallback.
        let mods = arguments.firstIndex(of: "--mods")
            .flatMap { arguments.count > $0 + 1 ? Int(arguments[$0 + 1]) : nil }
            ?? (AXMenuSearch.CmdModifiers.shift | AXMenuSearch.CmdModifiers.option)
        guard let item = AXMenuSearch.findItem(
                cmdChar: "S", modifiers: mods, inAppWithPID: pid),
              item.bool(kAXEnabledAttribute) ?? true
        else {
            print("no enabled Save As menu item at mods=\(mods)"
                  + " — open a document in the target first, or try another --mods")
            exit(1)
        }
        triggeredAt = Date()
        print("pressed Save As: \(item.perform(kAXPressAction))")
    }

    let listenUntil = Date().addingTimeInterval(listenFor)
    while Date() < listenUntil {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    watcher.stop()

    print("---")
    print("notifications received: "
          + (arrived.isEmpty ? "<none>" : arrived.joined(separator: ", ")))

    // If the controls were unreadable when the notification fired but are readable
    // now, a readiness wait is needed. If they were readable then, none is.
    if let panel = SavePanelLocator.findSavePanel(inAppWithPID: pid) {
        describeControls(of: panel, "after \(Int(listenFor))s")
        if let goto = SavePanelLocator.firstDescendant(
            withIdentifier: SavePanelLocator.ID.gotoSheet, in: panel, maxDepth: 3),
           let close = SavePanelLocator.firstDescendant(
            withIdentifier: SavePanelLocator.ID.gotoCloseButton, in: goto, maxDepth: 4) {
            print("closed goto sheet: \(close.perform(kAXPressAction))")
        }
        if let cancel = SavePanelLocator.firstDescendant(
            withIdentifier: SavePanelLocator.ID.cancelButton, in: panel,
            maxDepth: SavePanelLocator.controlDepth) {
            print("cancelled save panel: \(cancel.perform(kAXPressAction))")
        }
    } else {
        print("no save panel open at the end")
    }

case "help", "--help", "-h":
    print("""
    SaveAsHere — points an open save panel at the active document's folder.

    Usage:
      SaveAsHere                          Run as a background agent (⌃⌥⌘F)
      SaveAsHere run-once [--to <folder>] Perform the action once, then exit
      SaveAsHere trust [--prompt]         Report Accessibility permission state

    Diagnostics:
      SaveAsHere dump [--bundle <id>]     Dump an application's accessibility tree
      SaveAsHere dump-menu [--bundle <id>]  List menu items and key equivalents
      SaveAsHere document [--bundle <id>] Report a window's document attribute
      SaveAsHere trigger-save-as [--mods N]  Open a save panel via its menu item
      SaveAsHere probe-goto [--variant v] Send ⌘⇧G and dump the result
      SaveAsHere probe-settable           List settable attributes on the panel
      SaveAsHere probe-navigate --to <p>  Step-by-step navigation trace
      SaveAsHere probe-notifications      Report which AX notifications a save
                                          panel emits, and when it becomes usable
                                          [--seconds N] [--no-trigger]
      SaveAsHere cancel-panel             Dismiss any open panel without saving

    Without --bundle, the frontmost application is used.
    """)
    exit(0)

default:
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
