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

### Theme B — the App Group entitlement goes missing (**this diagnosis was wrong — see the postmortem**)

| PR | What happened |
|----|---------------|
| #21–#26 | Diagnostics: dump minted-profile / archived-app / `.xcent` entitlements to locate where `com.apple.security.application-groups` disappears |
| #23, #27 | Re-sign the archived binaries to force the App Group back in |
| #28 | Declare the App Groups capability in the generated project — **did not help** |
| #29 | Revert that experiment; keep the re-sign |

> **This section's premise was false.** It claimed Xcode 26 strips the App Group
> while packaging the archive, and everything built on that claim — the archive
> re-sign, the DER-entitlements flag, moving the re-sign after export — was
> chasing a symptom. Nothing was ever stripped: `xcodegen generate` was
> **overwriting the checked-in `.entitlements` files with an empty plist** before
> each build, so there was nothing in them to strip. See
> [the postmortem](#postmortem-what-was-actually-wrong) below. The text is left
> in place because the reasoning it caused is what the postmortem explains.

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
4. **App Group — fix the root cause first, keep the re-sign as a fallback.**
   See "Theme B best practices" below. Order: (a) both bundle IDs listed in the
   Matchfile, (b) App Groups capability enabled **and the specific group
   associated** on both App IDs in the portal, (c) `match` regenerates profiles
   that now inherit the group, (d) a post-build hook verifies the exported IPA
   carries `group.fi.mailhub.everybytecounts` and only re-signs (porting the
   current "Force the App Group entitlement…" logic) if it is still missing.
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

1. Create a **private git repo** for signing material, named for the Apple
   Developer **team**, not this app — e.g. `ssalonen/ios-signing`. One
   shared repo serves every app under the same team: the distribution cert is
   per-team (and capped by Apple), so match stores it once and reuses it, while
   profiles are namespaced by bundle ID. A future app just adds its bundle IDs to
   the same `Matchfile`. Split into separate repos **only** across different Apple
   teams, or when you need per-app access isolation (read access + `MATCH_PASSWORD`
   decrypts everything in the repo).
2. Generate an SSH key pair (`ssh-keygen -t ed25519`), add the **public** key as
   a read **deploy key** on the signing repo.
3. `fastlane match init` (point it at the repo's SSH URL), then seed once with
   `bundle exec fastlane match appstore` — creates/stores the distribution cert +
   both App Store profiles, encrypted with the `MATCH_PASSWORD` passphrase.
4. Add repo secrets: `MATCH_PASSWORD`, `MATCH_REPO_KEY` (the **private** key from
   step 2), and `MATCH_GIT_URL` (the SSH URL).

After that, every release runs `match --readonly` and never touches the portal.

## Theme B best practices (researched)

Community + Apple guidance on App Groups with `match` and app extensions
converges on one principle: **capabilities live on the App ID, and a
provisioning profile only ever inherits what its App ID already has.** This
reframes our nine-PR fight and tells us where the real fix belongs.

1. **List every bundle ID in the Matchfile** (`app_identifier` array must include
   both `fi.mailhub.everybytecounts` **and** `…​.widget`). If the extension's ID
   is omitted, `match` silently skips its profile and the build later dies with a
   *misleading* "profile doesn't support the App Group" error that points at the
   **app**, not the missing widget profile. [1]

2. **Enable the capability on the App ID, not in the Xcode project.** `match`
   regenerates a profile to match the App ID's *current* state; it cannot add a
   capability the App ID lacks, and there is **no App Store Connect API to
   register unknown/custom entitlements**. App Groups is a predefined capability,
   so it can be enabled — but the **specific group must be associated** with each
   App ID in the portal (or via `produce`) *before* running `match`. [2][3]
   - This is exactly why PR #28 ("declare the App Groups capability in the
     generated project") did nothing and was reverted in #29 — the project is the
     wrong layer. Our own `release.yml` diagnostic already suspected it: *"the App
     ID isn't handing the group to the profile … a portal/App-ID fix."*

3. **Then, and only then, verify + re-sign as a last resort.** With (1) and (2)
   correct, the minted profile authorises the group and the entitlements file
   requests it, so a manually-signed archive should carry it. If Xcode 26 *still*
   strips it during packaging (a narrower, real bug), the post-build re-sign is
   the escape hatch — but it stops being load-bearing.

4. **Watch the entitlement-key gotcha.** The iOS key is
   `com.apple.security.application-groups` (what our entitlements files use —
   correct). Some tooling/errors reference `com.apple.developer.app-groups`; a
   mismatch there produces a "profile doesn't include the … app-groups
   entitlement" error even when everything else is right. [4]

**Net:** the re-sign hack may well have been compensating for an App-ID-level
misconfiguration (group enabled but not associated). Doing (1)+(2) properly is
the best-practice fix and could retire the hack entirely; we keep the verify gate
permanently and the re-sign only as a guarded fallback.

### Sources

- [1] The fastlane Matchfile bundle-ID trap after adding a widget —
  https://dev.to/snake_sun/the-fastlane-matchfile-bundle-id-trap-that-killed-my-ci-after-adding-a-widget-j34
- [2] `match` force-generated profile does not include all capabilities —
  https://github.com/fastlane/fastlane/issues/15834
- [3] Creating profiles with managed capabilities / custom entitlements
  (templateName deprecated; enable on App ID via `produce`, then `match`) —
  https://github.com/fastlane/fastlane/discussions/29609
- [4] App Groups entitlement mismatch between profile and Xcode for an iOS app
  extension (Apple Developer Forums) —
  https://developer.apple.com/forums/thread/792656 and
  https://developer.apple.com/forums/thread/792648
- `match` action docs — https://docs.fastlane.tools/actions/match/

## Other risks / open questions

- **Two Apple accounts / no Mac in CI-only setups:** `match` seeding is the one
  step that needs a human with portal access; unavoidable regardless of tooling.

---

## Postmortem: what was actually wrong

**Symptom.** Releases v1.4.2–v1.4.5 shipped to TestFlight and opened to the
"Storage Unavailable" screen: `containerURL(forSecurityApplicationGroupIdentifier:)`
returned nil, so `MobileDataService.live` returned nil. CI was green for every one
of them.

**Root cause.** `project.yml` declared entitlements with XcodeGen's
`entitlements:` key and no `properties:`:

```yaml
    entitlements:
      path: App/EveryByteCounts/EveryByteCounts.entitlements
```

That key means *"generate this plist"*, not *"point at this file"*. XcodeGen's
`FileWriter.writePlist` overwrites the file at `path` unless the existing content
is identical to what it would write — and with no `properties:` what it writes is
an empty `<dict/>`. Every workflow runs `xcodegen generate` before building, so
**both `.entitlements` files were empty by the time Xcode or fastlane read them.**
The App Group was in git and nowhere else.

Xcode then did exactly what it was told: the archive log shows
`Write Auxiliary File Entitlements.plist`, and it wrote a `.xcent` with no App
Group because the file it was handed had none. Nothing was ever "stripped".

**Why every guard passed.** All of them compared the build against the same
emptied file:

- `entitlements.py check` looped `for key, value in declared.items()` over `{}` —
  zero iterations, nothing reported missing.
- The "parser-independent backstop" grepped that same empty file for `group\.`,
  got no matches, and never entered its loop.
- The re-sign's `merge()` merged an empty dict onto the signature, adding nothing,
  then verified with the same vacuous check.

The gates didn't fail to catch the bug — they passed *because of* it. Meanwhile the
embedded provisioning profiles did authorise
`com.apple.security.application-groups` all along, so `match`, the App IDs, and
the portal configuration were never at fault.

**Why the pre-fastlane pipeline seemed fine.** It hardcoded the group in the
workflow and forced it in with PlistBuddy, never reading the `.entitlements`
files. Commit `f8f5f96` "generalised" that to read the declared file — which
XcodeGen had already emptied. That commit is where silent breakage began, and
every fix after it was chasing consequences.

**The fix.** Stop letting a generator write a tracked file. `CODE_SIGN_ENTITLEMENTS`
now lives in `Config/App.xcconfig` / `Config/Widget.xcconfig`, which XcodeGen only
references; the `entitlements:` keys are gone. This is the same fix `7cdd513`
applied to `Info.plist` (`info:` → `INFOPLIST_FILE`) — entitlements just never got
it. The version moved to `Config/Version.xcconfig` for the same reason: the
release job used to regex-`sed` `MARKETING_VERSION` into the tracked `project.yml`.

The whole re-sign/DER apparatus is deleted. `verify_declared_entitlements` stays
and is now a real gate, because `entitlements.py` rejects an empty declared set
outright.

### Lessons

1. **Generators write only generated artifacts.** If a tool's config points at a
   tracked file, know whether it *reads* or *generates* it. XcodeGen's `info:` and
   `entitlements:` keys generate.
2. **A check whose expectation comes from the same source as the thing being
   checked is not a check.** Comparing a build against a file the build process
   can overwrite proves nothing. Assert the expectation is non-empty first.
3. **`git diff --exit-code` after codegen is the cheapest guard in this repo.** It
   would have caught this in seconds, in the first CI run. It now runs after every
   `xcodegen generate`.
4. **Don't build on an unverified mechanism.** "Xcode strips it" and
   "exportArchive re-signs from the stripped `.xcent`" were never tested directly;
   five fixes were layered on top of them.
5. **A green pipeline that ships a broken artifact is worse than a red one.**
   Prefer a gate that fails loudly to a workaround that "fixes" things silently.
