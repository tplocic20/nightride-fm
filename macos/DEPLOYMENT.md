# Nightride for macOS — deployment

Two distribution channels, both driven by **one git tag**:

| Channel | Workflow | Signing | Artifact | Lands in |
| --- | --- | --- | --- | --- |
| Direct download | `.github/workflows/macos-dmg.yml` | Developer ID + notarized | `Nightride.dmg` | A GitHub Release (download link) |
| Mac App Store | `.github/workflows/macos-appstore.yml` | Apple Distribution + App Sandbox | `Nightride.pkg` | App Store Connect |

The compiled binary is identical; only the signing/packaging/delivery differs.

---

## Cutting a release — one tag fans out

```bash
git tag v0.2.0
git push origin v0.2.0
```

That single `v*` tag triggers **both** workflows in parallel:

- **macos-dmg** builds → notarizes → publishes the `.dmg` on a GitHub Release.
- **macos-appstore** builds → signs → uploads the `.pkg` to App Store Connect.

The same `v*` tag also drives **iOS** (`ios-appstore.yml` → `.ipa` to App Store
Connect — see [../ios/DEPLOYMENT.md](../ios/DEPLOYMENT.md)). Only the DMG workflow
touches the GitHub Release, so they never collide. Each workflow also has a
**Run workflow** button (`workflow_dispatch`) for manual runs.

Version stamping (both channels): `CFBundleShortVersionString` comes from the tag
(`v0.2.0` → `0.2.0`); `CFBundleVersion` comes from the GitHub run number (monotonic,
which the App Store requires per upload). The source `App/Info.plist` keeps
placeholder values; CI overrides them per build.

> **iOS** hooks the same `v*` tag today (`ios-appstore.yml`). An Android Play
> Store workflow can hook it next.

After the App Store upload, the build appears under the app's macOS builds in
App Store Connect once processing finishes. **Metadata, screenshots, and
"Submit for Review" are done manually** in App Store Connect — the pipeline only
delivers the binary.

---

## One-time setup

You need a **paid Apple Developer Program** membership (Team ID `4527SA6RSX`).
Bundle id for both channels: `dev.plocic.nightride` — **shared with iOS**, so both
platforms live under one App Store Connect record (see [../ios/DEPLOYMENT.md](../ios/DEPLOYMENT.md)).

### A. Direct-download channel (Developer ID + notarization)

1. **Developer ID Application** certificate in your keychain
   (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application).
2. Export it (cert + private key) as a `.p12`.
3. Create an **app-specific password** at appleid.apple.com for notarization.

### B. Mac App Store channel

1. **Register the bundle id** `dev.plocic.nightride` (developer.apple.com ▸
   Identifiers ▸ App IDs). No special capabilities are needed — the App Sandbox
   is applied at sign time via `App/Nightride.appstore.entitlements`, not as an
   App ID capability.
2. **Create the app record** in App Store Connect (My Apps ▸ +): platform macOS,
   the bundle id above, an SKU, primary language.
3. **Certificates** (developer.apple.com ▸ Certificates):
   - **Apple Distribution** — signs the `.app`.
   - **Mac Installer Distribution** ("3rd Party Mac Developer Installer") — signs
     the `.pkg`.
   Export **both** (cert + key) into a **single combined `.p12`**
   (select both in Keychain Access ▸ right-click ▸ Export 2 items).
4. **Provisioning profile**: create a **Mac App Store** distribution profile for
   the bundle id, tied to the Apple Distribution cert; download the
   `.provisionprofile`.
5. **App Store Connect API key** (App Store Connect ▸ Users and Access ▸
   Integrations ▸ App Store Connect API): create a key with the **App Manager**
   role. Download the `AuthKey_XXXXXXXXXX.p8` (one-time download), and note the
   **Key ID** and **Issuer ID**.

---

## Repository secrets

Settings ▸ Secrets and variables ▸ Actions ▸ New repository secret.

### Direct-download (macos-dmg.yml)

| Secret | What |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | `base64 -i DeveloperID.p12` |
| `MACOS_CERT_PASSWORD` | password for that `.p12` |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
| `AC_NOTARY_APPLE_ID` | `hello@plocic.dev` |
| `AC_NOTARY_PASSWORD` | app-specific password |
| `AC_NOTARY_TEAM_ID` | 10-char Team ID |

### Mac App Store (macos-appstore.yml)

| Secret | What |
| --- | --- |
| `MAS_CERTS_P12_BASE64` | `base64 -i certs.p12` — combined Apple Distribution + Mac Installer certs |
| `MAS_CERTS_P12_PASSWORD` | password for that `.p12` |
| `MAS_APP_IDENTITY` | `Apple Distribution: Your Name (TEAMID)` |
| `MAS_INSTALLER_IDENTITY` | `3rd Party Mac Developer Installer: Your Name (TEAMID)` |
| `MAS_PROVISION_PROFILE_BASE64` | `base64 -i Nightride.provisionprofile` |
| `ASC_KEY_ID` | App Store Connect API key id (10 chars) |
| `ASC_ISSUER_ID` | App Store Connect API issuer id (uuid) |
| `ASC_API_KEY_P8_BASE64` | `base64 -i AuthKey_XXXXXXXXXX.p8` |

Tip: `base64 -i file | pbcopy` copies straight to the clipboard.

Until a channel's secrets are set, its workflow **fails fast at the preflight
step** with a clear message and produces no artifact.

---

## Local builds (no CI)

```bash
cd macos

bash build.sh                       # ad-hoc signed local test build → build/Nightride.app

bash release.sh                     # Developer ID → notarize → build/Nightride.dmg
SIGN_ONLY=1 bash release.sh         #   sign only (skip notarize/dmg)

bash release-appstore.sh            # Apple Distribution → .pkg → upload to App Store Connect
SIGN_ONLY=1 bash release-appstore.sh #   sign only (skip pkg/upload)
```

For local App Store runs, place the API key at
`~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8` and either install the
certs/profile in your keychain (auto-detected) or set the `MAS_*` /
`PROVISION_PROFILE` / `ASC_*` env vars (see the script header). Stamp a version
with `MARKETING_VERSION=0.2.0 BUILD_NUMBER=42 bash release-appstore.sh`.

---

## App Sandbox note

The App Store build is sandboxed (`App/Nightride.appstore.entitlements`):
`app-sandbox` + `network.client` (outbound HTTPS for the stream, the metadata
feed, and the user-tapped music links — the app's entire network surface). The
direct-download build is **not** sandboxed (`App/Nightride.entitlements`).
Discord Rich Presence — which needed an out-of-sandbox socket — was removed, so
there is no sandbox exception to request.
