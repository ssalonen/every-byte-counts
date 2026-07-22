# Migrating the signing & release flow to fastlane

## Why

The current TestFlight pipeline (`.github/workflows/release.yml`) works, but the
result is complicated and it took a long back-and-forth to get there. The pain
falls into two very different buckets — and only one of them is actually caused
by *how we manage signing*.

### Theme A — the signing / certificate dance (fastlane fixes this)

| PR | What went wrong | Current workaround |
|----|-----------------|--------------------|
| #9  | Secrets don't cross `workflow_call` | `secrets: inherit` + a "verify secrets present" gate |
| #10 | Cloud-managed cert → *"Cloud signing permission error"* | Import an Apple Distribution `.p12` into a throwaway keychain |
| #11 | `xcodebuild` automatic signing wants an **Admin** cloud-signing key to mint App Store profiles | `scripts/create_appstore_profiles.py` — a hand-signed ES256 JWT calling the ASC API to mint profiles |
| #20 | Automatic signing recreated certs → hit the **certificate cap** | Archive against the one imported cert, never let Xcode create one |

All four are symptoms of not having a managed signing store. **`match` removes
every one of them**: one distribution cert, reused everywhere; profiles synced
from an encrypted repo; no Admin/cloud-signing role required.

### Theme B — the App Group entitlement gets stripped (fastlane does NOT fix this)

| PR | What happened |
|----|---------------|
| #21–#26 | Diagnostics: dump minted-profile / archived-app / `.xcent` entitlements to locate where `com.apple.security.application-groups` disappears |
| #23, #27 | Re-sign the archived binaries to force the App Group back in |
| #28 | Declare the App Groups capability in the generated project — **did not help** |
| #29 | Revert that experiment; keep the re-sign |

Xcode 26 strips the App Group while packaging the archive. `build_app` (gym) is a
wrapper over the same `xcodebuild archive` / `-exportArchive`, so **switching to
fastlane will not automatically make this go away.** The plan below keeps a
verify gate and preserves the re-sign as a fallback hook.

## Decisions

- **Signing store:** `match` backed by a **private git repo**. Best "local dev
  setup easiness" (one `fastlane match appstore --readonly` and a teammate is
  set up), and it reuses a single cert so the cert-cap trap can't recur.
- **Scope:** CI release lanes **and** local lanes (`beta`, `build`). The local
  lanes are the whole point of the switch for day-to-day dev.
- **iOS only.** The reference article covers Android too; this repo has no
  Android target.
- Keep untouched: the Conventional-Commits versioning, coverage CI
  (`ci.yml` core-tests), changelog generation, GitHub Release step.

## Target layout

```
Gemfile                     # pins fastlane so CI and local match versions
fastlane/
  Appfile                   # bundle IDs + APPLE_TEAM_ID
  Fastfile                  # lanes: certificates, beta, build
  Matchfile                 # git storage, type: appstore
  Gymfile                   # scheme + export_method: app-store
```

### Lanes (`Fastfile`)

- `certificates` — `match(type: "appstore", readonly: is_ci)`; syncs the cert +
  both profiles (`fi.mailhub.everybytecounts`, `.widget`).
- `beta` — `setup_ci` → `app_store_connect_api_key(...)` →
  `match(api_key:, readonly:)` → `build_app` (archive the XcodeGen project) →
  **App Group verify + re-sign fallback** → `upload_to_testflight(api_key:)`.
  `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` passed via `xcargs` (build
  number stays `github.run_number`), so the existing versioning is untouched.
- `build` — local-only archive for a dev to sanity-check signing without upload.

Two details the reference article makes concrete and we adopt:
- **`setup_ci`** must run first on CI — it creates the temporary keychain
  `match` installs the cert into. Without it `match` fails on the runner.
- **`match(api_key: ...)`** and **`upload_to_testflight(api_key: ...)`** — feeding
  the ASC API key into both means **no `APPLE_ID` / password / 2FA login
  anywhere**, cleaner than the article's own secret list (it still carries
  `APPLE_ID` / `ITUNES_TEAM_ID`; we don't need either).

All App Store Connect auth reuses the existing secrets via a single
`app_store_connect_api_key` block: `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`.

### Where we deviate from the reference article (and why)

The article is a **React Native, enterprise-account, Android+iOS** guide; this
repo is a native, standard-Developer-Program, iOS-only app. So:

| Article | Here |
|---------|------|
| `Pods` / `pod install` / `npm` / `.xcworkspace` steps | Dropped — pure XcodeGen `.xcodeproj`, no CocoaPods/JS |
| `in_house: true` on the API key | `in_house: false` — enterprise-only flag; would break a normal TestFlight upload |
| Android lane + `slack` notifications | Omitted — no Android target, no Slack in this repo |
| `latest_testflight_build_number + 1` | Keep `github.run_number` — no extra ASC round-trip |
| New secret names (`APPSTORE_*`, `APPLE_ID`, `ITUNES_TEAM_ID`) | Keep existing `APPLE_TEAM_ID` + `APP_STORE_CONNECT_*`; API-key auth drops `APPLE_ID`/`ITUNES_TEAM_ID` entirely |
| (n/a — no App Group extension) | Keep the App Group verify + re-sign fallback (Theme B) |

## Work items

1. **Decouple signing from XcodeGen.** Remove `CODE_SIGN_STYLE: Manual`,
   `CODE_SIGN_IDENTITY`, and `PROVISIONING_PROFILE_SPECIFIER` from `project.yml`
   (both targets). fastlane injects signing at build time, so the generated
   project no longer has to line up with hand-minted profile names — this is a
   chunk of "the xcodegen issues." Debug/simulator builds keep automatic signing.
2. **Add `fastlane/` + `Gemfile`** as above.
3. **Rewrite `release.yml`.** Replace the ~10 keychain/profile/export steps with:
   checkout → `ruby/setup-ruby` (bundler cache) → **`webfactory/ssh-agent` loaded
   with `MATCH_REPO_KEY`** (so `match` can `git clone` the signing repo over SSH)
   → select Xcode → `brew install xcodegen` → `xcodegen generate` →
   `bundle exec fastlane beta`. Keep changelog, version-bump commit, and GitHub
   Release steps. Net: ~250 fewer lines.
4. **App Group safety net.** Register the capability properly via `match`, then a
   post-build hook re-checks the exported IPA for
   `group.fi.mailhub.everybytecounts` and, if missing, re-signs (porting the
   logic from the current "Force the App Group entitlement…" step) before upload.
5. **Delete** `scripts/create_appstore_profiles.py`.
6. **Secrets:** drop `APPLE_DIST_CERT_P12_BASE64` / `APPLE_DIST_CERT_PASSWORD`
   (the `.p12` now lives, encrypted, in the match repo). Add:
   - `MATCH_PASSWORD` — the passphrase that encrypts the match repo.
   - `MATCH_REPO_KEY` — the **private half** of an SSH key added as a **read
     deploy key** on the signing repo; loaded via `webfactory/ssh-agent` so CI
     can clone it.
   - `MATCH_GIT_URL` — the signing repo's SSH URL (referenced from `Matchfile`).

   `APPLE_TEAM_ID` + the three `APP_STORE_CONNECT_*` secrets stay unchanged.
7. **README + `.gitignore`.** Rewrite the "Distribution" section (new one-time
   setup + a "Local development signing" subsection); ignore `vendor/`,
   `fastlane/report.xml`, `fastlane/README.md`.

## One-time setup that must run on a Mac (not from CI)

These need a real macOS host and an Apple portal login, so they can't run in this
environment — the config will be ready and these are the only manual steps:

1. Create a **private git repo** for signing material (e.g.
   `ssalonen/everybytecounts-signing`).
2. Generate an SSH key pair (`ssh-keygen -t ed25519`), add the **public** key as
   a read **deploy key** on the signing repo.
3. `fastlane match init` (point it at the repo's SSH URL), then seed once with
   `bundle exec fastlane match appstore` — creates/stores the distribution cert +
   both App Store profiles, encrypted with the `MATCH_PASSWORD` passphrase.
4. Add repo secrets: `MATCH_PASSWORD`, `MATCH_REPO_KEY` (the **private** key from
   step 2), and `MATCH_GIT_URL` (the SSH URL).

After that, every release runs `match --readonly` and never touches the portal.

## Risks / open questions

- **App Group stripping may persist** (Theme B). The re-sign fallback covers it,
  so worst case the hack is preserved but hidden inside a fastlane hook instead
  of sprawled across the workflow. Best case, clean `match` profiles fix the root
  cause and the fallback is dead code we can later delete.
- **Two Apple accounts / no Mac in CI-only setups:** `match` seeding is the one
  step that needs a human with portal access; unavoidable regardless of tooling.
