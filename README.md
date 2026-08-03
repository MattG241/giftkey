# GiftKey

A barcode-scanning custom keyboard for iOS. Tap **Scan**, point the camera at a barcode,
and the code is typed into whatever field you were editing — in any app.

Built to replace ScanKey and Cognex Keyboard, both of which are gone. The specific job it
was written for: retail staff scanning third-party gift card barcodes (Code 128, 8-20
digit numeric) into the Shopify POS **Enter manually** gift card field on an iPhone.

**Free. No subscription, no in-app purchase, no ads, no scan limits, no account.**
There is no networking code in either target, so the App Store privacy label is
*Data Not Collected*.

---

## Contents

- [Requirements](#requirements)
- [Project layout](#project-layout)
- [Building](#building)
- **[Shipping without a Mac → `CI.md`](CI.md)**
- [Renaming / re-signing](#renaming--re-signing)
- [How it works](#how-it-works)
- [The post-processing pipeline](#the-post-processing-pipeline)
- [Adding a validation preset](#adding-a-validation-preset)
- [Memory budget](#memory-budget-read-before-touching-the-keyboard-target)
- [App Store submission](#app-store-submission)
- [App Store metadata (draft)](#app-store-metadata-draft)
- [Known limitations](#known-limitations)

---

## Requirements

- Xcode 15 or newer — **or** no Mac at all, building on Codemagic instead. See [`CI.md`](CI.md).
- iOS 16.0 deployment target
- A paid Apple Developer account (App Groups and keyboard extensions both require real
  provisioning; neither works with a free personal team)
- A physical device for anything camera-related

No third-party dependencies. No SPM packages, no CocoaPods, no Carthage.

## Project layout

```
GiftKey.xcodeproj          Checked in and ready to open
project.yml                XcodeGen spec to regenerate the project deterministically

Shared/                    Compiled into BOTH targets
  AppConstants.swift       ← every identifier lives here
  Settings.swift           Shared-UserDefaults-backed settings store
  ValidationPreset.swift   Named validation regexes
  ScanPostProcessor.swift  The pipeline. Pure functions, no UIKit
  BarcodeSymbology.swift   Symbology model + AVFoundation mapping
  CameraController.swift   AVCaptureSession wrapper (app-side scanning)
  ScanHandoff.swift        App Group handoff, 60 s expiry
  KeyboardPresence.swift   Keyboard heartbeat so the app can show install status
  Feedback.swift           Haptics and beeps

GiftKey/                   Containing app (SwiftUI)
  GiftKeyApp.swift         Entry point, giftkey:// URL handling
  VisionSymbology.swift    Vision mapping — app only, deliberately not Shared
  ScannerRepresentables.swift  VisionKit + AVFoundation engines for the in-app scanner
  Views/
    RootView.swift         Tabs
    SetupView.swift        Onboarding + live status + test field
    SettingsView.swift     The whole pipeline, with a live preview
    InAppScannerHomeView.swift  Scan tab / handoff endpoint
    ScannerScreen.swift    Full-screen scanner UI
    FAQView.swift          Why Full Access, what is collected (nothing)

GiftKeyKeyboard/           Keyboard extension (UIKit)
  KeyboardViewController.swift  Principal class: opens the app, types the result
  KeyboardIdleView.swift        The four keys
  KeyButton.swift               Key styling and hold-to-repeat
```

## Building

Open `GiftKey.xcodeproj`, select the **GiftKey** scheme and a real device, and build.
The keyboard extension is embedded automatically by the app target.

To regenerate the project after adding files:

```bash
brew install xcodegen
xcodegen generate
```

`project.yml` is the source of truth for target membership. Anything you drop in
`Shared/` is compiled into **both** targets — read the [memory budget](#memory-budget-read-before-touching-the-keyboard-target)
section before adding anything there.

To run the keyboard in the debugger: build and run the **GiftKey** scheme once to install
the app, then in Xcode choose *Debug > Attach to Process by PID or Name* and enter
`GiftKeyKeyboard`.

## Renaming / re-signing

The project currently ships under the prefix **`com.mattgroves`**. If you fork it or move
it to a different Apple team, these five places must all agree:

| What | Where | Current value |
|---|---|---|
| Bundle ID prefix | `Shared/AppConstants.swift` → `bundleIDPrefix` | `com.mattgroves` |
| App Group | `Shared/AppConstants.swift` → `appGroupID` | `group.com.mattgroves.giftkey` |
| App Group | `GiftKey/GiftKey.entitlements` | `group.com.mattgroves.giftkey` |
| App Group | `GiftKeyKeyboard/GiftKeyKeyboard.entitlements` | `group.com.mattgroves.giftkey` |
| Bundle IDs | `project.yml`, `codemagic.yaml`, and the target build settings | `com.mattgroves.giftkey`, `com.mattgroves.giftkey.keyboard` |

`DEVELOPMENT_TEAM` is set to `DNS7GY854U`. Codemagic overwrites it during the build via
`xcode-project use-profiles`, so it only matters for local Xcode builds.


Also update `CFBundleURLName` in `GiftKey/Info.plist` if you care about it being tidy
(the *scheme* itself, `giftkey`, does not need to change).

Rules the App Store enforces:

- The keyboard's bundle ID **must** be prefixed by the app's bundle ID.
  `com.acme.giftkey` and `com.acme.giftkey.keyboard` — not two unrelated IDs.
- The App Group must be registered on the developer portal and enabled on **both**
  App IDs, or the keyboard silently reads empty settings.

Sanity check after renaming: open the app, go to **Setup**. If the App Group is wrong you
get an explicit red warning there rather than a mysterious "settings do nothing" bug.

To rename the product from GiftKey to something else, change `CFBundleDisplayName` in
both `Info.plist` files, the target/product names in `project.yml`, and
`AppConstants.displayName`.

## How it works

### There is no camera in the keyboard, and there cannot be

iOS does not permit a keyboard extension to use the camera. Apple, on the developer
forums:

> "the camera is still not available to keyboard extensions. The only extension you can
> use the camera from is an iMessage Extension."
> — <https://developer.apple.com/forums/thread/681975>

This is not a permission or a Full Access gate. An `AVCaptureSession` inside a keyboard
extension configures perfectly — inputs and outputs all attach — and then never runs,
which presents as a solid black preview. Diagnosing that cost several build cycles;
hence this section.

### The round trip

1. The keyboard opens `giftkey://scan` by walking the responder chain to `openURL:`
2. The app launches straight into a full-screen scanner — VisionKit's
   `DataScannerViewController` where supported, the shared `CameraController` otherwise
3. The raw result is written to the App Group with a timestamp
4. The user taps the **← Back to \<app\>** breadcrumb iOS puts in the status bar
5. The keyboard consumes the handoff, runs it through `ScanPostProcessor`, and types it

Two extra taps versus scanning in place. Every camera-based keyboard wedge on iOS works
this way; the ones that appear to scan in place (Cognex, Honeywell, CodeCorp) are paired
with Bluetooth laser scanners rather than using the camera.

The handoff carries the **raw** value, not the processed one, so processing always
reflects the settings in force at insertion time. It is deleted on consumption and
expires after 60 seconds regardless. Batch mode accumulates several codes into one
handoff so the whole stack is typed on return.

## The post-processing pipeline

Applied in order to every scan, from either path. Configured in **Settings**, with a live
preview at the top of that screen that runs the real pipeline against a sample.

1. **Trim whitespace, strip control characters.** Always on. Code 128 FNC characters and
   Codabar start/stop characters get stripped here.
2. **Strip EAN/UPC check digit.** Optional. Applies to EAN/UPC symbologies, or — when
   the symbology is unknown — to anything that looks like a GTIN.
3. **UPC-A ↔ EAN-13.** Optional. AVFoundation reports UPC-A as a 13-digit EAN-13 with a
   leading zero, so both directions are a leading-zero add/remove.
4. **Regex find and replace.** Optional, single rule, `$1`-style templates supported.
5. **Prefix and suffix strings.** Optional.
6. **Validation filter.** Optional. The whole processed code must match. A failure means
   **nothing is typed** — the keyboard shakes and fires an error haptic instead.
7. **Suffix keystroke** (`None` / `Return` / `Tab`), or the **batch separator** when
   batch mode is on.

Note on ordering: the original spec put the suffix keystroke before validation. It runs
after here on purpose — validating a code with `\n` already glued to the end would force
every pattern to carry a trailing `\n?`. The keystroke is transport, not part of the code.

## Adding a validation preset

Open `Shared/ValidationPreset.swift`:

```swift
static let myPreset = ValidationPreset(
    id: "my-preset",             // stable forever - it is persisted in UserDefaults
    name: "My preset",           // shown in the picker
    detail: "What it accepts.",  // shown under the picker
    pattern: "^[A-Z]{2}[0-9]{6}$"
)
```

Then add it to the `all` array:

```swift
static let all: [ValidationPreset] = [off, giftCard, numericAny, myPreset, custom]
```

That is the entire job. `SettingsView` renders `all` automatically and the pipeline
resolves by `id`. **Never change an existing `id`** — users who selected it would be
silently reset to Off.

## Memory budget (read before touching the keyboard target)

iOS gives a keyboard extension roughly **60-70 MB** before jetsam kills it. A kill looks
to the user like the keyboard "crashing" back to the system keyboard mid-transaction.

Since the camera moved out of the extension this stopped being a live risk — the keyboard
now does nothing but draw four buttons, read UserDefaults, and call `insertText`. But the
ceiling still applies, so:

- **Keep `Shared/` light.** Everything in it is compiled into the keyboard as well as the
  app. `GiftKey/VisionSymbology.swift` lives app-side precisely so the extension never
  links Vision.
- **Do not add frameworks to the extension target** without checking what they cost.

## App Store submission

### Review gotchas specific to keyboard extensions

- **Guideline 4.4.1 forbids advertising inside an extension view.** No ads in the
  keyboard, ever. (GiftKey has none anywhere.)
- **Full Access will be questioned.** Answer it in the review notes before they ask —
  see the template below.
- **The keyboard must be usable without the camera.** It ships with a globe key, delete
  key and return key so it is never a dead end, and it explains itself when Full Access
  or camera permission is missing instead of showing a black view. Reviewers do test the
  denied-permission path.
- **The containing app must do something.** An app that is only an installer for a
  keyboard gets rejected as minimal functionality. GiftKey's app is a working standalone
  scanner with copy-to-clipboard, plus setup and settings.
- **Test on the reviewer's likely path:** install, add keyboard, deny Full Access, try to
  scan. That flow must be clear and non-broken.

### Privacy label answers

App Store Connect > App Privacy: choose **"Data Not Collected"** and answer *No* to every
category. That is accurate — verify it yourself with section 18 of `TEST_PLAN.md` before
submitting, and re-verify if you ever add a dependency.

Because nothing is collected, no privacy policy URL is strictly required, but supply one
anyway; it is a two-line page and it heads off questions.

### Review notes template

> GiftKey is a barcode-scanning keyboard. Staff in retail scan gift card barcodes
> directly into a point-of-sale field.
>
> **Why Full Access (RequestsOpenAccess) is required:**
> 1. The user's settings (validation filter, prefix/suffix, barcode types) are stored in
>    a shared App Group container, which a keyboard cannot read without Full Access.
> 2. The Scan key opens the containing app to use the camera, which a keyboard cannot do
>    without Full Access. The keyboard extension itself never touches the camera — iOS
>    does not permit that for any keyboard.
>
> GiftKey contains **no networking code of any kind** in either the app or the keyboard —
> no analytics, no crash reporting, no advertising SDK, no third-party dependencies. It
> never reads the contents of the text field; it only inserts into it. Nothing is stored
> or transmitted. The privacy label is "Data Not Collected" and is accurate.
>
> **To test:** install, add the GiftKey keyboard, enable Allow Full Access, open Notes,
> switch to GiftKey and tap Scan. Any barcode works — a product barcode on any packaging
> is fine. The in-app "Scan" tab also works standalone without the keyboard.
>
> The keyboard degrades gracefully: with Full Access off it displays instructions rather
> than failing, and remains usable as a basic keyboard (globe, delete, return).

### Category

**Utilities.** (Business is a defensible second choice, but Utilities matches how people
search for this.)

## App Store metadata (draft)

**Name (30 char limit)**
`GiftKey: Barcode Keyboard` (25)

**Subtitle (30 char limit)**
`Scan barcodes into any app` (26)

**Alternatives if the name is taken:**
- `ScanKeys: Barcode Keyboard` / `Scan straight into any field`
- `Barcode Keyboard: GiftKey` / `Free scanner keyboard`

**Promotional text (170 char limit)**

> Free forever. No subscription, no scan limits, no ads, no data collected. Scan a
> barcode and it types straight into whatever field you are in — including POS gift
> card fields.

**Description**

> **GiftKey turns your camera into a keyboard.**
>
> Tap into any text field, switch to the GiftKey keyboard, and tap Scan. GiftKey opens
> to the camera, you scan, and the code is typed straight into the field you came from.
> It works in every app — your point of sale, Notes, Safari, spreadsheets, ticketing
> systems, inventory tools, anything with a text field.
>
> Built for retail staff who scan gift cards, vouchers and product codes into a POS all
> day and are tired of reading digits off a card and typing them by hand.
>
> **FREE, PROPERLY FREE**
> No subscription. No in-app purchases. No scan limits. No ads. No account. No trial.
>
> **NOTHING IS COLLECTED**
> GiftKey contains no networking code at all. Not disabled — absent. Barcodes are decoded
> on your device by Apple's own frameworks and typed into your field. Nothing is stored,
> nothing is uploaded, and GiftKey never reads what is already in the field.
>
> **THE GIFT CARD GUARD**
> Turn on the built-in "Gift card (8-20 digits)" filter and GiftKey will refuse to type
> anything that is not 8 to 20 digits. Scan a product barcode by mistake and nothing
> happens — the keyboard shakes instead of putting the wrong number in a gift card field.
>
> **EVERY COMMON BARCODE**
> Code 128, Code 39, Code 93, EAN-13, EAN-8, UPC-A, UPC-E, ITF-14, Interleaved 2 of 5,
> Codabar, QR, Data Matrix, PDF417 and Aztec. Turn off the ones you never use to make
> scanning faster and misreads less likely.
>
> **SHAPE THE OUTPUT**
> • Add a prefix or suffix
> • Strip EAN/UPC check digits
> • Convert between UPC-A and EAN-13
> • Find and replace with a regular expression
> • Press Return or Tab automatically after each code
> • Custom validation patterns of your own
>
> **BATCH MODE**
> Keep the camera running and scan a whole stack. Separate codes with Return, Tab or a
> comma and fill a spreadsheet column without touching the screen.
>
> **HOW IT WORKS**
> Tap Scan and GiftKey opens to the camera. Scan the barcode, tap the back arrow at the
> top left, and the code is typed into the field you were in. Two taps.
>
> iOS does not allow any keyboard to use the camera directly - that is an Apple
> restriction, not a GiftKey limitation. Every camera-based scanner keyboard works this
> way.
>
> **ABOUT FULL ACCESS**
> GiftKey needs it to read your settings and to open its own app to scan. That is the
> whole reason. There is no networking code in GiftKey —
> nothing can leave your device even in principle. The FAQ inside the app explains this
> in plain language.

**Keywords (100 char limit, comma separated, no spaces)**

```
barcode,scanner,keyboard,scan,gift card,scanner keyboard,barcode keyboard,pos,retail,qr,code128,upc
```

*(Do not repeat words already in the name or subtitle — "GiftKey", "Barcode" and
"Keyboard" are already indexed from those fields. Trim to fit 100 characters.)*

**Search intent being targeted:** people whose ScanKey or Cognex Keyboard stopped
working. Terms worth covering across name, subtitle and keywords: *barcode keyboard*,
*scanner keyboard*, *scan to text field*, *gift card scanner*, *scan into any app*,
*ScanKey replacement*.

**Category:** Utilities
**Age rating:** 4+
**Price:** Free

**Screenshots to produce** (6.7" and 6.5" required):
1. The keyboard open over a POS gift card field, mid-scan, reticle on a barcode.
2. The code sitting in the field, keyboard back to the Scan button.
3. Settings showing the gift card validation filter.
4. A rejection: "Code rejected by filter" with the shake.
5. Batch mode filling a spreadsheet.
6. The FAQ screen, with "No scan data is stored or transmitted" visible.

## Known limitations

- **Some numeric-only fields do not offer a keyboard switcher.** If a host app forces a
  number pad with no globe key, no custom keyboard can be selected there. Scanning in the
  GiftKey app and pasting is the workaround. Worth testing per POS app.
- **Opening the containing app from the keyboard** walks the responder chain to whatever
  implements `openURL:`. It uses only public API and is long-established practice, but it
  is not a documented, supported call. If a future iOS release breaks it, the user can
  still open GiftKey from the Home Screen and scan — the handoff works the same way. The
  code handles the failure and says so on screen.
- **VisionKit's `DataScannerViewController` requires A12 Bionic or newer.** The in-app
  scanner falls back to the shared AVFoundation controller automatically on older
  devices; there is no user-visible difference beyond the guidance overlay.
- **Haptics inside a keyboard extension require Full Access.** Without it they silently
  do nothing, which is the documented behaviour.
- **No unit tests yet.** `ScanPostProcessor` is deliberately pure and UIKit-free so a
  test target can be added without touching anything else — that is the obvious first
  place to add coverage.
