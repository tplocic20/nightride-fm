# Nightride for iOS — deployment

One distribution channel, driven by the **same git tag** as macOS:

| Channel | Workflow | Signing | Artifact | Lands in |
| --- | --- | --- | --- | --- |
| App Store / TestFlight | `.github/workflows/ios-appstore.yml` | Apple Distribution + App Store profile | `Nightride.ipa` | App Store Connect |

(For sideloading to your own device with a free Apple ID — no CI, no App Store —
see [README.md](README.md). This file is about the App Store pipeline.)

---

## Cutting a release — one tag fans out

```bash
git tag v0.2.0
git push origin v0.2.0
```

That single `v*` tag triggers **all** store workflows in parallel:

- **macos-dmg** builds → notarizes → publishes the `.dmg` on a GitHub Release.
- **macos-appstore** builds → signs → uploads the `.pkg` to App Store Connect.
- **ios-appstore** builds → signs → uploads the `.ipa` to App Store Connect.

Only the DMG workflow touches the GitHub Release, so they never collide. Each
workflow also has a **Run workflow** button (`workflow_dispatch`) for manual runs.

Version stamping: `MARKETING_VERSION` (→ `CFBundleShortVersionString`) comes from
the tag (`v0.2.0` → `0.2.0`); `CURRENT_PROJECT_VERSION` (→ `CFBundleVersion`)
comes from the GitHub run number (monotonic, which the App Store requires per
upload). `project.yml` keeps placeholder values; CI overrides them per build.

After the upload, the build appears under the app's iOS builds / TestFlight in
App Store Connect once processing finishes. **Metadata, screenshots, and
"Submit for Review" are done manually** in App Store Connect — the pipeline only
delivers the binary.

---

## One-time setup

You need a **paid Apple Developer Program** membership (Team ID `4527SA6RSX`).

iOS and macOS **share one bundle id `dev.plocic.nightride` and one App Store
Connect record** (a single "Nightride.fm Player" app available on iPhone, iPad,
and Mac). The **Apple Distribution certificate** and the **App Store Connect API
key** are account-wide and already exist from the macOS channel
([macos/DEPLOYMENT.md](../macos/DEPLOYMENT.md)). So all iOS adds is its own
provisioning profile for the shared id, plus the iOS platform on the record.

1. **Register / reuse the App ID** `dev.plocic.nightride` (developer.apple.com ▸
   Identifiers ▸ App IDs), an **explicit** App ID — Apple's explicit App IDs span
   iOS, iPadOS, macOS, tvOS, watchOS, and visionOS, so one App ID serves both
   platforms. No special capabilities needed for the default build. (Add
   **CarPlay** only once you intend to ship it — see below.)
2. **Use the existing app record** — do **not** create a second app. Open the
   "Nightride.fm Player" record in App Store Connect and **add the iOS platform**
   to it (the iOS build shares the macOS record because the bundle id matches).
   If you haven't created the record yet, create it with both platforms under
   `dev.plocic.nightride`.
3. **Apple Distribution certificate** — the same one the macOS App Store build
   uses (account-wide). If you don't have it yet: developer.apple.com ▸
   Certificates ▸ + ▸ Apple Distribution. Export it (cert + private key) as a `.p12`.
4. **Provisioning profile**: create an **iOS App Store** distribution profile for
   `dev.plocic.nightride`, tied to the Apple Distribution cert; download the
   `.mobileprovision`. (This is separate from the *Mac* App Store profile — same
   App ID, one profile per platform.)
5. **App Store Connect API key** (App Store Connect ▸ Users and Access ▸
   Integrations ▸ App Store Connect API): the same key as macOS. If you don't
   have one, create a key with the **App Manager** role, download the
   `AuthKey_XXXXXXXXXX.p8` (one-time download), and note the **Key ID** and
   **Issuer ID**.

---

## Repository secrets

Settings ▸ Secrets and variables ▸ Actions ▸ New repository secret.

### Reused from the macOS App Store channel (already set — nothing to do)

| Secret | What |
| --- | --- |
| `MAS_CERTS_P12_BASE64` | Combined `.p12`; its Apple Distribution cert signs iOS too |
| `MAS_CERTS_P12_PASSWORD` | password for that `.p12` |
| `MAS_APP_IDENTITY` | `Apple Distribution: Your Name (TEAMID)` |
| `ASC_KEY_ID` | App Store Connect API key id (10 chars) |
| `ASC_ISSUER_ID` | App Store Connect API issuer id (uuid) |
| `ASC_API_KEY_P8_BASE64` | `base64 -i AuthKey_XXXXXXXXXX.p8` |

### New for iOS (add this one)

| Secret | What |
| --- | --- |
| `IOS_PROVISION_PROFILE_BASE64` | `base64 -i Nightride.mobileprovision` — the iOS **App Store** profile |

Tip: `base64 -i file | pbcopy` copies straight to the clipboard.

Until the iOS secret is set, the workflow **fails fast at the preflight step**
with a clear message and produces no artifact.

---

## Local builds (no CI)

```bash
cd ios

brew install xcodegen                # one-off
bash build.sh                        # generate the .xcodeproj for Xcode / sideload

bash release-appstore.sh             # Apple Distribution → .ipa → upload to App Store Connect
SIGN_ONLY=1 bash release-appstore.sh #   build the signed .ipa, skip validate/upload
```

For local App Store runs, place the API key at
`~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`, drop the
`.mobileprovision` at `App/Nightride.mobileprovision` (or set `PROVISION_PROFILE`),
and make sure the Apple Distribution cert is in your keychain (auto-detected, or
pin it with `IOS_APP_IDENTITY`). Set `ASC_KEY_ID` / `ASC_ISSUER_ID`. Stamp a
version with `MARKETING_VERSION=0.2.0 BUILD_NUMBER=42 bash release-appstore.sh`.

The script reads the profile's UUID, Name, and Team straight from the
`.mobileprovision`, installs it where Xcode expects it, and signs **manually**
with Apple Distribution — your everyday Xcode/sideload flow (Automatic signing in
`project.yml`) is left untouched.

---

## CarPlay note

The default App Store build signs against `App/Nightride.entitlements` (empty),
so it works with any App Store profile. CarPlay needs the restricted
`com.apple.developer.carplay-audio` entitlement, which Apple grants on request
(<https://developer.apple.com/contact/carplay/>, pick **Audio**). Once granted:

1. Add the **CarPlay** capability to the App ID and regenerate the App Store
   provisioning profile so it carries `carplay-audio`; update
   `IOS_PROVISION_PROFILE_BASE64`.
2. Build with `CARPLAY=1` — `release-appstore.sh` then signs against
   `App/Nightride.carplay.entitlements`. (To make CI do this, add
   `CARPLAY: "1"` to the build step's `env` in `ios-appstore.yml`.)

The entitlements you sign with must be a subset of what the profile authorizes,
so keep CarPlay **off** until both the App ID and the profile carry it.
