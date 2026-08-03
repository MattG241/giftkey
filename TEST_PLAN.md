# GiftKey test plan

Run the whole list on a real device before every App Store submission. The Simulator
has no camera, so it can only verify layout, settings persistence and the rejection
path — everything marked **device** must be run on hardware.

Note the flow throughout: the keyboard has no camera (iOS forbids it), so scanning always
means tap Scan → GiftKey opens → scan → tap the back breadcrumb → code is typed.

Record the device, iOS version and build number at the top of each run.

```
Device:        iPhone ____________   iOS ______
Build:         1.0 (____)
Tester / date: ____________________
```

---

## 1. Install and first run

- [ ] Fresh install. App opens on **Setup**, status reads "Keyboard not set up yet".
- [ ] Tap **Open Settings** — Settings.app opens on the GiftKey page.
- [ ] Add the keyboard via Settings > General > Keyboard > Keyboards > Add New Keyboard.
- [ ] Return to GiftKey. Status still reads "not set up" (Full Access is still off).
- [ ] Enable Allow Full Access, accept the system warning.
- [ ] Switch to the GiftKey keyboard once in any app, then reopen GiftKey.
- [ ] Setup status flips to **"Keyboard is ready"** with a "Last active …" timestamp.
- [ ] No "App Group is not configured" warning is visible. *(If it is, the entitlement
      and `AppConstants.appGroupID` do not match — see README.)*

## 2. Core scan into a text field — **device**

The flow under test is: tap Scan → GiftKey opens to the camera → scan → tap the
**← Back to <app>** breadcrumb iOS puts in the status bar → code is typed.

- [ ] **Notes.** Focus a note, switch to GiftKey, tap Scan. GiftKey opens to the camera.
      Scan a Code 128 barcode, tap the back breadcrumb. Digits appear in the note.
- [ ] **Safari.** Same, into a search field. Nothing is submitted automatically.
- [ ] **POS-style numeric field.** Use Shopify POS > gift card > *Enter manually*, or any
      field with `keyboardType = .numberPad`.
      - [ ] The globe key is available so GiftKey can be selected. *(Some numeric-only
            fields do not offer a keyboard switcher at all — record which apps.)*
      - [ ] The scanned code lands in the field and POS accepts it.
- [ ] Scan the **same barcode twice quickly** (within 2 s) — it is inserted once only.
- [ ] Scan the same barcode again after 3 s — it is inserted a second time.
- [ ] Delete key removes one character per tap; hold repeats.
- [ ] Return key inserts a newline.
- [ ] Globe key switches keyboards; long-press shows the keyboard picker.

## 3. Full Access off

- [ ] Turn Full Access **off** in Settings, then open the keyboard in Notes.
- [ ] Keyboard shows the red message naming the exact Settings path. It does **not**
      crash and does **not** show a black rectangle.
- [ ] The Scan button is visibly disabled and tapping it does nothing destructive.
- [ ] Re-enable Full Access — the keyboard works again without reinstalling.

## 4. Camera permission denied — **device**

- [ ] Settings > GiftKey > Camera **off**.
- [ ] Tap Scan in the keyboard. GiftKey opens and shows the permission screen with a
      working **Open Settings** button — not a black rectangle.
- [ ] Re-enable camera access — scanning works again.

## 5. Low light and torch — **device**

- [ ] In a dim room, in the GiftKey app's scanner, tap the torch button.
- [ ] Torch turns on, icon turns yellow, barcode decodes.
- [ ] Tap Close. **Torch turns off immediately.** *(A torch left on after dismissal is a
      one-star review.)*
- [ ] Background the app mid-scan. Torch is off.

## 6. Focus

- [ ] Tap the preview — a yellow focus square appears at the tap point and the image
      refocuses.
- [ ] Hold a barcode ~10 cm away. Continuous autofocus locks on without a tap.

## 7. Post-processing pipeline

Use Settings > Preview to check each transform before testing live, then confirm with a
real scan.

- [ ] **Trim.** A Code 128 payload with leading/trailing spaces inserts clean.
- [ ] **Strip check digit.** EAN-13 `9312345678907` inserts as `931234567890`.
- [ ] **UPC-A to EAN-13.** 12-digit input gains a leading `0`.
- [ ] **EAN-13 to UPC-A.** 13-digit input starting `0` loses it.
- [ ] **Find and replace.** Pattern `^GC` / template `` strips a `GC` prefix.
- [ ] Invalid regex shows the red "Not a valid regular expression" warning and is treated
      as a no-op — it never crashes.
- [ ] **Prefix / suffix.** Both appear around the code.
- [ ] **Suffix keystroke = Return.** A newline follows the code in Notes.
- [ ] **Suffix keystroke = Tab.** A tab follows the code (test in a spreadsheet app).

## 8. Validation filter — the safety guardrail

- [ ] Select **Gift card (8-20 digits)**.
- [ ] Scan a valid 13-digit gift card — inserts normally.
- [ ] Scan a **QR code** containing a URL — rejected. Keyboard shakes, error haptic
      fires, message reads "Code rejected by filter", **nothing is typed**.
- [ ] Scan a 7-digit code — rejected.
- [ ] Reposition and rescan the *same rejected code* — it is re-evaluated rather than
      silently ignored by the debounce.
- [ ] Select **Custom regex**, enter `^[0-9]{4}$`. Only 4-digit codes insert.
- [ ] Enter a deliberately broken regex (`^[0-9`). The warning shows and scans are
      rejected with "Validation regex is invalid" rather than inserting garbage.
- [ ] Set filter to **Off** — everything inserts again.

## 9. Batch mode — **device**

- [ ] Enable Batch mode, separator **Tab**.
- [ ] Open a spreadsheet app (Numbers) and focus a cell.
- [ ] Tap Scan. In GiftKey's scanner, scan five different barcodes without closing it —
      the camera stays live and the counter climbs to `5 scanned`.
- [ ] Tap Close, then the back breadcrumb.
- [ ] All five land, each in its own cell, separated by tabs.
- [ ] Repeat with separator **Return** into Notes — one code per line.

## 10. Round trip

- [ ] In Notes, switch to GiftKey. The primary button reads **Scan**.
- [ ] Tap it — GiftKey opens straight into the full-screen scanner.
- [ ] Scan a code. The Scan tab shows "Code ready" and the handoff banner.
- [ ] Switch back to Notes. As soon as the GiftKey keyboard appears, the code is typed.
- [ ] The code is typed **once only** — leave and re-enter the field; it does not repeat.
- [ ] **Expiry.** Scan in app, wait more than 60 seconds, then return to the keyboard.
      Nothing is typed.
- [ ] Post-processing and the validation filter apply to the inserted code.
- [ ] Copy-to-clipboard on the Scan tab puts the processed code on the clipboard.

## 11. Memory — **device**

The keyboard no longer runs a camera, so the old jetsam risk is largely gone. Still worth
a sanity pass:

- [ ] Open and dismiss the keyboard 30 times. It never flashes back to the system
      keyboard (that would be a jetsam kill).
- [ ] Do a round trip 20 times in a row. No slowdown, no missed insertions.

## 12. Orientation

- [ ] Keyboard lays out correctly in portrait and landscape; all four keys reachable.
- [ ] Rotate the in-app scanner in both directions — the preview re-orients correctly and
      is not stretched or sideways.
- [ ] No layout constraint errors in the console.

## 13. Small screen — iPhone SE — **device**

- [ ] All keyboard controls are visible and tappable in portrait and landscape.
- [ ] Setup and Settings screens scroll without clipped text.

## 14. Appearance

- [ ] Light mode: keys are light on a grey keyboard background, text is legible.
- [ ] Dark mode: keys are dark, the Scan button stays clearly the primary action.
- [ ] Switch appearance while the keyboard is on screen — colours update without a
      restart.

## 15. Feedback settings

- [ ] Beep on scan **off** — a successful scan is silent, haptic still fires.
- [ ] Haptic on scan **off** — no vibration, beep still plays.
- [ ] Both off — insertion still works.
- [ ] Rejection haptic is clearly different from the success haptic.

## 16. Symbology toggles

- [ ] All types on by default on a fresh install.
- [ ] Turn off QR. A QR code no longer decodes at all (not "decodes then rejects").
- [ ] Turn off everything except Code 128 — attempting to turn off the last remaining
      type does nothing (at least one must stay on).
- [ ] Apply **gift card preset** — filter set to 8-20 digits, transforms cleared,
      symbologies reduced to the retail set.

## 17. Privacy verification

This is the app's headline claim, so verify it rather than trusting it.

- [ ] `grep -rniE "URLSession|NSURLConnection|CFNetwork|Alamofire|https?://" --include=*.swift Shared GiftKey GiftKeyKeyboard`
      returns nothing. *(Restrict to `*.swift` — the Info.plist files contain the Apple
      DTD URL in their doctype, which is not networking code.)*
- [ ] Xcode > Debug > Network — no connections while scanning.
- [ ] Run the app in Instruments with the Network template through a full scan cycle —
      zero connections attributed to GiftKey.
- [ ] No third-party package dependencies in the project.

## 18. Regression sweep before submission

- [ ] Delete the app, reinstall, and run sections 1 and 2 again from scratch.
- [ ] Archive builds cleanly for a real device with no signing warnings.
- [ ] The keyboard appears in Settings under the correct display name.
