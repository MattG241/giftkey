# Demo codes for App Review

Apple rejected GiftKey under **Guideline 2.1(a) — Information Needed**:

> We need a demo QR code or AR marker (image) to fully assess the app features.

A barcode-scanning keyboard cannot be assessed without something to scan, and a
reviewer at a desk has no gift card to hand. The files here are that something.

Regenerate them with:

```bash
python tools/make_demo_barcodes.py --verify
```

`--verify` decodes every PNG back with an independent decoder (zxing-cpp) and fails
the run rather than letting an unscannable image ship. Install the dependencies with
`pip install pillow segno zxing-cpp`.

## The files

| File | What it is |
|---|---|
| `giftkey-demo-codes.png` | All four codes on one page, with the expected result under each. **This is the one to attach to the reply in App Store Connect.** |
| `giftkey-demo-1-code128-giftcard-16.png` | Code 128, `6034551234567890` |
| `giftkey-demo-2-code128-giftcard-8.png` | Code 128, `90210457` |
| `giftkey-demo-3-ean13-product.png` | EAN-13, `9310072011691` |
| `giftkey-demo-4-qr-text.png` | QR, `GIFTKEY-DEMO-QR` |

The single-code files are there so a reviewer can display one code full-screen on a
second device; the sheet is for printing or for a monitor.

The codes are not live gift card numbers and reach nothing — they are numbers of the
right shape, generated from the symbology specs. GiftKey has no networking code, so
nothing is looked up in any case.

## What to reply to App Review

Attach `giftkey-demo-codes.png` to the reply in App Store Connect (Resolution Center
accepts image attachments), also add the notes below to **App Review Information →
Notes**, and say the same thing in the reply:

> GiftKey is a barcode-scanning keyboard, so the "demo content" it needs is simply
> barcodes to scan. We have attached a sheet of four demo codes
> (giftkey-demo-codes.png). Please display it on a second screen or print it — the
> app scans it with the device camera. No account, login or demo data is required;
> the app has no accounts and no server.
>
> **To test, end to end:**
> 1. Install GiftKey and open it. The Setup tab has an Open Settings button; in
>    Settings add the GiftKey keyboard (Keyboards › Add New Keyboard › GiftKey) and
>    turn on Allow Full Access.
> 2. Return to the Setup tab. Step 3 has a test field — tap it, then press the globe
>    key until the GiftKey keyboard appears. (Any other app works the same way:
>    Notes, Safari, a point-of-sale field.)
> 3. Tap **Scan**. GiftKey opens to the camera. Point it at code 1 on the attached
>    sheet.
> 4. Tap the back arrow at the top left. `6034551234567890` is typed into the field
>    you started in.
>
> **To see the validation guard rail** (the feature the app exists for): in GiftKey ›
> Settings set Validation to "Gift card (8-20 digits)", then scan code 4 (the QR code,
> payload `GIFTKEY-DEMO-QR`). Nothing is typed, the keyboard shakes and an error
> haptic fires — a non-gift-card code is refused rather than dropped into a
> point-of-sale gift card field.
>
> **The app also works standalone**, without the keyboard: the Scan tab scans and
> copies to the clipboard, so all four codes can be assessed without adding the
> keyboard at all.
>
> The codes on the sheet are Code 128 (16 and 8 digits), EAN-13 and QR, which cover
> the four decode paths in the app.

The Full Access explanation stays as it is in the review notes template in the main
[`README.md`](../../README.md#review-notes-template) — this section is in addition to
it, not a replacement.
