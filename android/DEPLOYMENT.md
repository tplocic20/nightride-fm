# Android — Play Store release (CI/CD)

Tag-based, lockstep with the Apple stores. `scripts/release.sh x.y.z` bumps the
Android `versionName` + `versionCode` along with macOS/iOS, then pushes a
`vX.Y.Z` tag. That tag triggers
[`.github/workflows/android-playstore.yml`](../.github/workflows/android-playstore.yml),
which builds a **signed `.aab`** from the tagged commit and uploads it to the
**Internal testing** track on Google Play. Promote to production from the Play
Console.

(For the build details of the local debug app see [README.md](README.md). This
file is about the Play Store pipeline.)

## One-time setup

Until the secrets below exist the workflow fails fast at **preflight** (an inert
no-op), exactly like the Apple workflows did before their secrets were set.

### 1. Play Console app + first manual release

The Play Publishing API **cannot do the very first release** — a human must ship
one build before the API can take over. So, once:

1. Create the app in the **Play Console** with package `dev.plocic.nightride`.
2. Complete the mandatory gates: **privacy policy URL** (e.g. `https://plocic.dev`
   or the repo), content rating, **Data safety** form, target audience, store
   listing.
3. Enrol in **Play App Signing** (recommended): Google holds the *app signing
   key*; you sign uploads with an *upload key* (the keystore below).
4. Build one signed `.aab` and upload it to **Internal testing** by hand. After
   that, CI publishes every tagged release.

### 2. Upload keystore

Generate a dedicated upload key (with Play App Signing this is **not** the final
app-signing key — Google re-signs):

```bash
keytool -genkeypair -v -keystore upload.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Tomasz Plocic, O=plocic.dev, C=PL"
# (prompts for a store password and a key password — they may be the same)

base64 -i upload.jks | pbcopy   # → ANDROID_KEYSTORE_BASE64
```

Keep `upload.jks` safe and **out of git** (`*.jks` is gitignored). Losing the
upload key is recoverable via Play support; losing the app-signing key (when you
*don't* use Play App Signing) is not — which is why Play App Signing is advised.

### 3. Play service account (API publishing)

1. **Play Console ▸ Setup ▸ API access** — link a Google Cloud project (let Play
   create one if you have none).
2. In that **Google Cloud** project: enable the **Google Play Android Developer
   API**, create a **service account**, add a **JSON key**, and download it.
3. Back in **Play Console ▸ Users & permissions**: invite the service account's
   email and grant it app access with at least **Release to testing tracks**
   (or admin for this app). Permissions can take a few minutes to propagate.

### 4. Repository secrets

Add under **Settings ▸ Secrets and variables ▸ Actions**:

| Secret | Value |
|--------|-------|
| `ANDROID_KEYSTORE_BASE64`   | base64 of `upload.jks` (step 2) |
| `ANDROID_KEYSTORE_PASSWORD` | the store password you chose |
| `ANDROID_KEY_ALIAS`         | `upload` |
| `ANDROID_KEY_PASSWORD`      | the key password you chose |
| `PLAY_SERVICE_ACCOUNT_JSON` | the whole service-account JSON (step 3) |

## Releasing

Same one command as the Apple stores — Android just comes along for the ride:

```bash
bash scripts/release.sh 0.6.0    # bump all 3 → commit → tag v0.6.0 → push
```

The tag fans out; `android-playstore` builds the tagged commit and lands a new
build on the **Internal testing** track. `versionCode` is derived from the
semver (`major*1e6 + minor*1e3 + patch`), so it's always unique and increasing.

## Direct-download APK (GitHub Release)

The same `v*` tag also triggers
[`.github/workflows/android-apk.yml`](../.github/workflows/android-apk.yml),
which builds a signed `.apk` and attaches it to the **GitHub Release** next to the
macOS `.dmg` — the sideload / direct-download channel (link it from plocic.dev,
share it in Discord). It needs only the four keystore secrets (no Play service
account), so it ships even if Play isn't configured.

⚠️ **Parallel channel, not interchangeable.** This APK is signed with your
**upload key**; the Play Store re-signs with Google's app key (Play App Signing).
So an install from GitHub and an install from Play have different signatures and
**cannot update each other** — a user picks one channel. Expected for a
community / sideload app.

## How CI signs

`app/build.gradle.kts` resolves the release `signingConfig` from
`keystore.properties` locally, or from `ORG_GRADLE_PROJECT_*` Gradle properties
on CI (which the workflow feeds from the secrets above). With neither present,
release builds are left unsigned and only debug builds — so contributors and
forks build fine without any of this.
