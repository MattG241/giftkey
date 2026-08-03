# Shipping GiftKey without a Mac

The whole loop, start to finish:

```
push to git  →  Codemagic builds on macOS  →  TestFlight  →  your iPhone
                                                                  ↓
                              App Store Connect (browser)  ←  you test
```

No Mac at any point. `codemagic.yaml` in the repo root drives it.

---

## Progress

| Step | Status |
|---|---|
| 1. Repo on GitHub | Done — `MattG241/giftkey`, private |
| 2. Codemagic connected | Done |
| 3. `compile-check` green | Done |
| 4. Apple portal: App IDs + App Group | **Next** |
| 5. ASC API key into Codemagic | **Next** |
| 6. Replace placeholders | Done — prefix `com.mattgroves` |
| 7. App icon | **Next — hard gate** |
| 8. Tag → TestFlight | |
| 9. Device testing | |
| 10. Submit for review | |

## Order of operations

Steps 1-3 need nothing from Apple. Steps 4, 5 and 7 are the remaining blockers before a
build can reach TestFlight.

### 1. Get the repo onto GitHub

Codemagic builds from a git remote.

```bash
git remote add origin https://github.com/MattG241/giftkey.git
git push -u origin main
```

Make it **private** unless you want the source public. Codemagic's free tier works with
private repos.

### 2. Connect Codemagic

1. Sign up at codemagic.io with your GitHub account.
2. Add the `giftkey` repository.
3. Codemagic detects `codemagic.yaml` automatically — there is nothing to configure in
   their UI for the build itself.

### 3. Run `compile-check` until it is green

This workflow needs **no Apple account, no signing, no placeholder replacement**. It only
answers "does it compile?".

This code has never been through a compiler, so expect the first run to fail. Read the
log, fix locally, push, repeat. Each round is roughly 5-8 minutes.

Two things that make this less painful:

- **Batch your fixes.** The log lists every error in the file it got to, not just the
  first. Fix all of them before pushing.
- **Swift stops at the first failing file.** Once a file compiles clean, the next push
  surfaces errors in the *next* file. It gets faster as you go.

### 4. Set up the Apple side

You have the developer account, so this is portal work in a browser:

**a. Two App IDs** — Certificates, Identifiers & Profiles > Identifiers:

| Identifier | Capabilities |
|---|---|
| `com.mattgroves.giftkey` | App Groups |
| `com.mattgroves.giftkey.keyboard` | App Groups |

The keyboard's ID **must** be prefixed by the app's. This is enforced.

**b. One App Group** — Identifiers > App Groups: `group.com.mattgroves.giftkey`.
Then go back into *both* App IDs and tick that group under the App Groups capability.
Missing this on the keyboard is the single most common cause of "settings do nothing".

**c. An App Store Connect API key** — Users and Access > Integrations > App Store Connect
API > **+**. Give it **App Manager** access. Download the `.p8` **once** — Apple will not
let you download it again. Note the Key ID and Issuer ID.

**d. The app record** — App Store Connect > Apps > **+** > New App. Bundle ID
`com.mattgroves.giftkey`, SKU anything, name and language as per the README metadata.

### 5. Give Codemagic the API key

Codemagic > Teams > your team > **Integrations** > App Store Connect > Add key.

Upload the `.p8`, paste the Key ID and Issuer ID, and **name it exactly**:

```
GiftKey ASC Key
```

That string is referenced in `codemagic.yaml` under `integrations:`. If you name it
something else, change it in both places.

### 5b. Signing certificate private key

Apple stores signing **certificates** but never **private keys**. A certificate created
on someone's Mac (or by another CI service) is therefore useless to Codemagic — it can
download the certificate and still not be able to sign with it. The symptom is:

```
Cannot save Signing Certificates without certificate private key
```

The fix is to give Codemagic its own key and let it issue a certificate against that.

**Generate a key** (once, ever — reuse it for every build and every future app):

```bash
openssl genrsa -out giftkey_cert_key.pem 2048
```

Keep it somewhere safe and **outside the repo**. `.gitignore` covers `*.pem`-adjacent
secrets, but the simplest protection is not to put it in the working tree at all.

**Add it to Codemagic:** Codemagic → your app → **Environment variables**

| Field | Value |
|---|---|
| Variable name | `CERTIFICATE_PRIVATE_KEY` |
| Value | the entire file contents, including the `-----BEGIN/END PRIVATE KEY-----` lines |
| Group | `signing` |
| Secure | **ticked** |

The group name `signing` is referenced by `codemagic.yaml`. Get it wrong and the
variable is simply absent, which the workflow now catches with a clear error rather
than letting it fail deep inside the signing step.

**Certificate limit:** Apple caps distribution certificates per account (2 for most
individual accounts). If `--create` reports the maximum has been reached, revoke an
unused one at Certificates, Identifiers & Profiles → Certificates. Revoking a
certificate does **not** affect apps already on the App Store — only future builds
signed with it.

### 6. Replace the placeholders — DONE

Identifiers are already set throughout to the `com.mattgroves` prefix:

- `Shared/AppConstants.swift` — `bundleIDPrefix`, `appGroupID`
- `GiftKey/GiftKey.entitlements` — App Group
- `GiftKeyKeyboard/GiftKeyKeyboard.entitlements` — App Group
- `codemagic.yaml` — `BUNDLE_ID`, `KEYBOARD_BUNDLE_ID`
- `GiftKey/Info.plist` — `CFBundleURLName`
- `project.yml`, `GiftKey.xcodeproj` — `PRODUCT_BUNDLE_IDENTIFIER` on both targets

`DEVELOPMENT_TEAM` is set to the real Team ID `DNS7GY854U`. `xcode-project
use-profiles` overwrites it at build time regardless, so it only matters locally.

The release workflow refuses to run if `PLACEHOLDER` reappears in `AppConstants.swift` or
either entitlements file, so a half-finished rename fails in 10 seconds rather than 10
minutes into a confusing signing error.

### 7. Add an app icon

**This is a hard gate** — the archive fails App Store validation without it.

Produce a 1024×1024 PNG, **no transparency, no rounded corners** (Apple rounds it), and
drop it into `GiftKey/Assets.xcassets/AppIcon.appiconset/` alongside the existing
`Contents.json`, then add the filename to that JSON:

```json
{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Xcode 15 generates every other size from that one file.

### 8. Ship a build to TestFlight

```bash
git tag v1.0.0
git push origin v1.0.0
```

The tag is what triggers `ios-release`. Pushing to `main` never releases anything.

Roughly 10 minutes later the build appears in TestFlight. Install TestFlight on your
iPhone, accept the internal tester invite, and install GiftKey.

### 9. Test on the device

Work through `TEST_PLAN.md`. Sections 2-5 are the ones that decide whether this is
usable behind a counter.

**What you lose without a Mac:** section 12 (memory) assumes Xcode's memory gauge. You
cannot run it as written. Proxy it instead:

- Open and cancel the scanner 30-40 times in a row. If the keyboard ever flashes back to
  the system keyboard, that is a jetsam kill and it is a real problem.
- Scan continuously in batch mode for 2-3 minutes.
- Do both with several heavy apps already open.

If it survives that on your oldest available iPhone, you are probably fine. It is a
weaker signal than the gauge — worth borrowing a Mac for an hour before 1.0 if you can.

### 10. Submit for review

TestFlight upload does **not** submit for review — `submit_to_app_store: false` is
deliberate. When you are happy:

App Store Connect > your app > prepare the listing (metadata drafted in `README.md`),
attach the build, fill in the privacy label as **Data Not Collected**, paste the review
notes template from the README, and hit Submit.

---

## Costs

| | |
|---|---|
| Codemagic free tier | 500 build min/month — a build here is ~5-8 min |
| Apple Developer Program | ~$149 AUD/year (you have this) |
| Everything else | Free |

## Troubleshooting

**"Cannot save Signing Certificates without certificate private key"** — see step 5b.
Apple never stores private keys, so a certificate created elsewhere cannot be used here.

**"Provisioning profile ... doesn't include the App Groups capability"** — the App Group
is not enabled on the App ID. Note that this is *two* steps on the portal, and the second
is easy to miss: tick **App Groups** in the capabilities list, then click **Edit** next to
it and select `group.com.mattgroves.giftkey`. Ticking the box alone assigns nothing.
Do it for **both** App IDs.

Then delete the existing profiles under **Profiles** — changing an App ID's capabilities
invalidates them, and `fetch-signing-files` may otherwise reuse a stale one. They are
regenerated on the next build by `--create`.

**"No matching provisioning profile"** — the keyboard's App ID does not exist, or does
not have App Groups enabled. Both App IDs need profiles; the `fetch-signing-files` step
in the release workflow creates them with `--create`, but the *identifiers* must exist
first.

**Build succeeds, settings do nothing on device** — the App Group is not enabled on the
keyboard's App ID, or the string does not match `AppConstants.appGroupID` exactly. The
app's Setup tab shows an explicit red warning when this is wrong.

**"Invalid bundle. Missing app icon"** — step 7.

**Upload rejected, duplicate build number** — build numbers must strictly increase. The
workflow uses Codemagic's `$PROJECT_BUILD_NUMBER`, which does that automatically. If you
ever rebuild a tag, bump the tag rather than re-running.

**Keyboard does not appear in Settings on device** — the extension was not embedded.
Confirm `GiftKeyKeyboard.appex` is in the build artifacts.
