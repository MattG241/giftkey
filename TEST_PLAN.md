# GiftKey test plan

Run the whole list on a real device before every App Store submission. The Simulator
has no camera, so it can only verify layout, settings persistence and the rejection
path — everything marked **device** must be run on hardware.

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

- [ ] **Notes.** Focus a note, switch to GiftKey, tap Scan, scan a Code 128 barcode.
      Digits appear in the note. Camera stops and the keyboard returns to the Scan button.
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
- [ ] In-keyboard: tap Scan. A red message points at Settings; the keyboard shakes; no
      crash, no frozen black preview.
- [ ] In-app: open the Scan tab and tap Scan. The permission screen appears with a
      working **Open Settings** button.
- [ ] Re-enable camera access — both paths work again.

## 5. Low light and torch — **device**

- [ ] In a dim room, in-keyboard scanning, tap the torch button.
- [ ] Torch turns on, icon turns yellow, barcode decodes.
- [ ] Tap Cancel. **Torch turns off immediately.** *(A torch left on after dismissal is a
      one-star review.)*
- [ ] Switch away from the keyboard mid-scan (Home, or switch keyboards). Torch is off.
- [ ] Same checks in the in-app full-screen scanner.

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
- [ ] Scan five different barcodes without leaving the keyboard.
- [ ] All five land, each in its own cell, and the on-screen counter reads `5 scanned`.
- [ ] Camera stays live between scans; a green flash confirms each one.
- [ ] Tap Cancel to stop. Counter resets on the next batch run.
- [ ] Repeat with separator **Return** into Notes — one code per line.

## 10. Path B — scan in app

- [ ] Settings > Scan mode > **In app**.
- [ ] In Notes, switch to GiftKey. The primary button reads **Scan in app**.
- [ ] Tap it — GiftKey opens straight into the full-screen scanner.
- [ ] Scan a code. The Scan tab shows "Code ready" and the handoff banner.
- [ ] Switch back to Notes. As soon as the GiftKey keyboard appears, the code is typed.
- [ ] The code is typed **once only** — leave and re-enter the field; it does not repeat.
- [ ] **Expiry.** Scan in app, wait more than 60 seconds, then return to the keyboard.
      Nothing is typed.
- [ ] Post-processing and the validation filter apply to Path B results exactly as they
      do to Path A.
- [ ] Copy-to-clipboard on the Scan tab puts the processed code on the clipboard.

## 11. Path A failure fallback

Hard to force on healthy hardware. If you have a device where the in-keyboard camera
cannot start:

- [ ] The keyboard reports the failure and the **Scan in app** button appears.
- [ ] The fallback stays visible for the rest of the session.

## 12. Memory pressure — **device**

The keyboard extension is killed by jetsam somewhere around 60-70 MB.

- [ ] Attach Xcode > Debug > Attach to Process > `GiftKeyKeyboard`.
- [ ] Open the keyboard and start scanning. Watch the memory gauge.
- [ ] Steady-state while scanning stays comfortably under 50 MB.
- [ ] Start and cancel the scanner **20 times in a row**. Memory returns to the idle
      baseline each time — no upward staircase (that would mean a session or preview
      layer is being retained).
- [ ] With the scanner running, open several heavy apps to trigger memory pressure. The
      keyboard shows "Camera stopped to free memory" rather than disappearing.
- [ ] The keyboard is never killed and re-created mid-scan (visible as the keyboard
      flashing back to the system keyboard).

## 13. Orientation

- [ ] Portrait: keyboard is taller while scanning; preview is usable; controls reachable.
- [ ] Rotate to landscape **while scanning**. Preview re-orients correctly, is not
      stretched or sideways, and the keyboard does not exceed 62% of the screen.
- [ ] Rotate back. No layout constraint errors in the console.
- [ ] Rotate the in-app full-screen scanner in both directions.

## 14. Small screen — iPhone SE — **device**

- [ ] All keyboard controls are visible and tappable in portrait.
- [ ] Landscape scanning is still usable — the preview is short but the reticle fits.
- [ ] Setup and Settings screens scroll without clipped text.

## 15. Appearance

- [ ] Light mode: keys are light on a grey keyboard background, text is legible.
- [ ] Dark mode: keys are dark, the Scan button stays clearly the primary action.
- [ ] Switch appearance while the keyboard is on screen — colours update without a
      restart.

## 16. Feedback settings

- [ ] Beep on scan **off** — a successful scan is silent, haptic still fires.
- [ ] Haptic on scan **off** — no vibration, beep still plays.
- [ ] Both off — insertion still works.
- [ ] Rejection haptic is clearly different from the success haptic.

## 17. Symbology toggles

- [ ] All types on by default on a fresh install.
- [ ] Turn off QR. A QR code no longer decodes at all (not "decodes then rejects").
- [ ] Turn off everything except Code 128 — attempting to turn off the last remaining
      type does nothing (at least one must stay on).
- [ ] Apply **gift card preset** — filter set to 8-20 digits, transforms cleared,
      symbologies reduced to the retail set.

## 18. Privacy verification

This is the app's headline claim, so verify it rather than trusting it.

- [ ] `grep -rniE "URLSession|NSURLConnection|CFNetwork|Alamofire|https?://" --include=*.swift Shared GiftKey GiftKeyKeyboard`
      returns nothing. *(Restrict to `*.swift` — the Info.plist files contain the Apple
      DTD URL in their doctype, which is not networking code.)*
- [ ] Xcode > Debug > Network — no connections while scanning.
- [ ] Run the app in Instruments with the Network template through a full scan cycle —
      zero connections attributed to GiftKey.
- [ ] No third-party package dependencies in the project.

## 19. Regression sweep before submission

- [ ] Delete the app, reinstall, and run sections 1 and 2 again from scratch.
- [ ] Archive builds cleanly for a real device with no signing warnings.
- [ ] The keyboard appears in Settings under the correct display name.
