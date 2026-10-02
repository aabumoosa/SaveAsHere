# SaveAsHere

A small, free, open-source macOS menu-bar agent that moves the **Save As** panel to the
folder of the document you are working on — automatically, the moment the panel appears.

It keeps the filename the application suggested, and it **never completes the save**.
Confirming or cancelling is always yours.

<p align="center">
  <img src="docs/images/menubar.png" alt="SaveAsHere's ⤓ icon in the macOS menu bar" width="124">
</p>

> [النسخة العربية في الأسفل](#بالعربية)

---

## Important: you build it yourself

There is **no downloadable app** in this repository. You build it from the source code on
your own Mac — it takes a few minutes and the steps are below.

The reason: running a downloaded app without warnings requires the author to sign it with
a paid Apple *Developer ID* and have Apple notarize it. This project does not do that, so
a prebuilt copy would be blocked by Gatekeeper. Building locally avoids the problem, and
you can read every line of code before you grant it permission to control other apps.

## What it does

1. You choose **Save As…** in an application.
2. The panel appears. SaveAsHere reads which document the window belongs to.
3. If the panel is showing some other folder, SaveAsHere moves it to that document's
   folder. If it is already there, SaveAsHere does nothing.
4. You press Save (or Cancel) yourself.

There is also a manual shortcut, **⌃⌥⌘F**, for a panel that is already open.

## Status

Tested on macOS 26.6 and macOS 27.

| Application | Result |
|---|---|
| TextEdit, Preview, Word, Excel, Xcode, VS Code | Works |
| Numbers, Pages | Not supported yet — they do not expose the document's path through Accessibility. Planned via Apple Events |
| Apps with their own custom save dialogs (most Adobe apps) | Cannot be supported — there is no standard folder field to drive |

Be aware that in testing, most of the supported apps **already opened the panel in the
document's folder** when the document had just been opened from disk. SaveAsHere is most
useful when an app remembers a different "last used" folder. Full measurements:
[`docs/findings/app-support.md`](docs/findings/app-support.md).

---

## Build and install

### Requirements

- macOS 14 (Sonoma) or later.
- Swift 6 toolchain — install **Xcode 16+** or just the Command Line Tools:

  ```bash
  xcode-select --install
  ```

  Check with `swift --version`; it should report 6.0 or later.

### Step 1 — Get the code

```bash
git clone https://github.com/aabumoosa/SaveAsHere.git
cd SaveAsHere
```

(Or use **Code → Download ZIP** on GitHub and unzip it.)

### Step 2 — Create a signing certificate (one time only)

macOS ties the Accessibility permission to the app's code signature. Without a stable
signature, every rebuild silently invalidates the permission, while System Settings still
shows it as enabled — so the app looks broken when it is not. A free self-signed
certificate solves this:

1. Open **Keychain Access**.
2. Menu **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Fill in:
   - Name: `SaveAsHere Dev`
   - Identity Type: `Self Signed Root`
   - Certificate Type: `Code Signing`
4. Click **Create**.

Then tell the build script to use it:

```bash
export SAH_SIGN_IDENTITY="SaveAsHere Dev"
```

If you already have an Apple Development certificate in your keychain, the script will
pick it up automatically and you can skip this step.

### Step 3 — Build

```bash
swift test                 # optional: runs the 48 unit tests
./Scripts/build-app.sh     # produces build/SaveAsHere.app
```

### Step 4 — Install and grant permission

```bash
cp -R build/SaveAsHere.app /Applications/
open /Applications/SaveAsHere.app
```

1. macOS asks for **Accessibility** permission. Open
   **System Settings → Privacy & Security → Accessibility** and enable **SaveAsHere**.
2. **Quit and relaunch** SaveAsHere (the permission is read only at launch).
3. The **⤓** icon appears in the menu bar.

To start it automatically, add it in
**System Settings → General → Login Items → Open at Login**.

### Updating

After pulling new code, rebuild and **copy it to /Applications again** — building alone
does not replace the copy that is running:

```bash
git pull
./Scripts/build-app.sh
pkill -f SaveAsHere.app; cp -R build/SaveAsHere.app /Applications/
open /Applications/SaveAsHere.app
```

### Uninstalling

Quit it from the ⤓ menu, delete `/Applications/SaveAsHere.app`, and remove its permission:

```bash
tccutil reset Accessibility com.abumoosa.saveashere
```

---

## Using it

The ⤓ menu shows:

- **Last outcome** — what happened on the last panel. This matters, because SaveAsHere
  deliberately does nothing in many situations, and without this line "nothing happened"
  would look the same as "it is broken".
- **Enabled** — turn the agent on or off.
- **Automatic here** — turn automatic mode off for the current application only.
  The ⌃⌥⌘F shortcut still works there.

Log file: `~/Library/Logs/SaveAsHere.log`

### Troubleshooting

| Symptom | Fix |
|---|---|
| Nothing happens, and the menu asks for permission | Grant Accessibility, then quit and relaunch |
| Permission is enabled but still nothing happens | The signature changed (usually an ad-hoc build). Run `tccutil reset Accessibility com.abumoosa.saveashere`, then grant it again |
| Works in some apps but not others | Check the Status table above |

## How it works

1. Finds the save panel by its accessibility identifier (`save-panel`).
2. Reads the document's path from the window that owns the panel (`AXDocument`).
3. Opens the panel's "Go to folder" sheet (⌘⇧G), writes the path, and reads it back.
4. Confirms with Return — **only** after checking that the sheet is still open and that
   keyboard focus is in its path field, so the Return cannot reach the Save button.
   If either check fails, nothing is sent and the sheet is closed.
5. Verifies afterwards that the filename did not change.

Every element is found by its accessibility identifier, not by its English title, so it
works on non-English systems. It was developed with an Arabic keyboard layout, which is
why every synthesised keystroke states its character explicitly — otherwise ⌘⇧G is a
silent no-op under a non-Latin layout.

## Limitations

These come from macOS itself:

- **Cannot be sandboxed**, so it cannot be distributed through the Mac App Store.
- **Requires Accessibility permission.**
- **Folder confirmation is approximate.** The panel exposes only the current folder's
  *name*, not its path, so two folders with the same name cannot be told apart. When the
  change cannot be confirmed, the agent reports "unverified" instead of claiming success.
- **A Return keystroke is unavoidable.** The "Go to folder" sheet has no confirm button and
  no accessibility action that confirms it. The safety gate above bounds the risk.

## Comparison with Default Folder X

[Default Folder X](https://www.stclairsoft.com/DefaultFolderX/) is the well-known
commercial utility for Open and Save dialogs on the Mac.

| | SaveAsHere | Default Folder X |
|---|---|---|
| Price | Free, MIT licensed | Paid ($39.95 per user at the time of writing) |
| Source | Open | Closed |
| Scope | One job: move Save As to the document's folder | A full toolkit: folder menus, favourites with shortcuts, recent folders, jump to any Finder window, and more |
| Permissions | Accessibility only | Accessibility, and more for some features |
| Installation | Build from source | Signed, ready-to-run app |
| Maturity | New | Developed for more than 20 years |

If you want a complete file-dialog toolkit, Default Folder X is the mature choice.
SaveAsHere is for people who want only this one behaviour, in a small app whose code they
can read.

## Development

```bash
swift build
swift test                                          # 48 tests
./.build/debug/SaveAsHere help                      # all diagnostic commands
./.build/debug/SaveAsHere run-once                  # act once on the frontmost app's panel
./.build/debug/SaveAsHere run-once --to ~/Documents # force a target folder, for testing
```

The most important tests are the adversarial ones: they drive the navigator against a fake
panel that misbehaves on purpose, and check that Return is never sent when focus is outside
the path field, when focus cannot be read, or when the "Go to folder" sheet has vanished.

### Layout

```
Sources/AXKit/        Accessibility wrapper — the only module that touches AX APIs
Sources/SaveAsCore/   Pure decision logic, unit-tested against fakes
Sources/SaveAsHere/   Real AX implementations, the agent, and diagnostics
Tests/                Unit tests for SaveAsCore
docs/findings/        What was actually observed, per application and per macOS version
```

## License

[MIT](LICENSE) — you may use, modify and redistribute it freely, including commercially,
as long as you keep the copyright notice. It comes with no warranty.

---

## بالعربية

**SaveAsHere** أداة مجانية مفتوحة المصدر لنظام macOS، تعمل في شريط القوائم. عندما تفتح
نافذة «حفظ باسم» في أي برنامج، تنقلها الأداة تلقائيًا إلى مجلد المستند الذي تعمل عليه،
وتُبقي اسم الملف المقترح كما هو. ولا تضغط زر الحفظ أبدًا؛ فالحفظ أو الإلغاء قرارك أنت.

### لا توجد نسخة جاهزة للتنزيل

يجب أن تبني البرنامج بنفسك من الكود على جهازك. والسبب أن تشغيل برنامج مُنزَّل بلا تحذيرات
يحتاج توقيعًا مدفوعًا من Apple (Developer ID) واعتمادًا منها، وهذا المشروع لا يستعمله.
والبناء المحلي يحل المشكلة، ويتيح لك أن تراجع الكود قبل أن تعطيه صلاحية التحكم في البرامج.

### خطوات البناء باختصار

1. ثبّت أدوات المطوّر: `xcode-select --install` (يلزم Swift 6 فما فوق، وmacOS 14 فما فوق).
2. نزّل الكود: `git clone` ثم `cd SaveAsHere`.
3. أنشئ شهادة توقيع مرة واحدة من **Keychain Access ← Certificate Assistant ← Create a
   Certificate**، باسم `SaveAsHere Dev` ونوع `Self Signed Root` و`Code Signing`، ثم:
   `export SAH_SIGN_IDENTITY="SaveAsHere Dev"`.
   هذه الخطوة مهمة؛ فبدونها يُبطل macOS صلاحية Accessibility بصمت مع كل بناء جديد.
4. ابنِ: `./Scripts/build-app.sh`
5. ثبّت: `cp -R build/SaveAsHere.app /Applications/` ثم افتحه.
6. فعّل الصلاحية من **System Settings ← Privacy & Security ← Accessibility**، ثم أغلق
   البرنامج وافتحه من جديد. ستظهر أيقونة ⤓ في شريط القوائم.

التفاصيل الكاملة وحل المشكلات في القسم الإنجليزي أعلاه.

### ما يعمل الآن

يعمل في TextEdit وPreview وWord وExcel وXcode وVS Code. ولا يعمل بعد في Numbers وPages،
ولا في البرامج التي لها نوافذ حفظ خاصة بها مثل أكثر برامج Adobe.

### الترخيص

MIT: يحق لأي شخص أن يستعمل الكود ويعدّله ويعيد نشره، حتى تجاريًا، بشرط أن يُبقي إشعار
حقوق المؤلف. والبرنامج مقدَّم كما هو بلا أي ضمان.
