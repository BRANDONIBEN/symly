# Shipping Symly

Two tracks: **publish to GitHub** and **ship a signed + notarized install** so it
opens with no Gatekeeper warning. Do them in this order.

Status of the gating items from `BEFORE-PUSH.md`:
- Contact email: resolved (`symly@brandoniben.com`).
- "Uncommitted release edits": the repo has no commits yet, so the first commit
  below covers it.
- Site download flow (`DOWNLOAD_URL`, Supabase): lives in the `symly-site` repo,
  wire it after the DMG exists (Track B, step 5).

---

## Track A: GitHub

The repo is already `git init`ed on `main` with a safe `.gitignore` (it excludes
`.build/`, `dist/`, `*.dmg`, `*.app`, and secrets like `*.p12` / notary creds).
`gh` is logged in as `BRANDONIBEN`.

```sh
cd ~/Documents/mxf-mediaorganizer

# 1. First commit (source only; build artifacts + secrets are gitignored)
git add -A
git commit -m "Symly: initial public release"

# 2. Create the repo and push (public, open source)
gh repo create symly --public --source=. --remote=origin --push \
  --description "Organize Avid Media Composer's MXF media by project with one symlink. No copies, no moves, no deletes."
```

After Track B produces the notarized DMG:

```sh
# 3. Tag + release, attach the DMG
git tag v0.1.0 && git push origin v0.1.0
gh release create v0.1.0 dist/Symly-0.1.0.dmg \
  --title "Symly 0.1.0" \
  --notes "First release. Signed + notarized for macOS 13+."
```

`gh release create` prints the asset URL — that is the site's `DOWNLOAD_URL`.

---

## Track B: Signed + notarized install

### One-time setup (needs your Apple login — only you can do these)

1. **Developer ID Application certificate.** You have the membership but no cert
   in your keychain yet. Create one:
   - Xcode > Settings > Accounts > (your team) > Manage Certificates > `+` >
     **Developer ID Application**. (Or developer.apple.com > Certificates.)
   - Confirm it landed: `security find-identity -v -p codesigning | grep "Developer ID Application"`
   - Note your **Team ID** (the 10-character code in the cert name / on the
     developer.apple.com membership page).

2. **Notarization credentials**, stored once as a keychain profile:
   - Make an **app-specific password** at appleid.apple.com (Sign-In & Security >
     App-Specific Passwords). This is NOT your Apple ID password.
   - Store it:
     ```sh
     xcrun notarytool store-credentials symly-notary \
       --apple-id "you@example.com" --team-id "YOURTEAMID" --password "xxxx-xxxx-xxxx-xxxx"
     ```

### Each release

```sh
cd ~/Documents/mxf-mediaorganizer/app
SIGN_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" ./build_release.sh
```

`build_release.sh` builds release, signs with Developer ID + hardened runtime,
makes a drag-to-install DMG, notarizes (waits for Apple), staples, and verifies
with `spctl`. The script never sees your password; `notarytool` reads the keychain
profile. Output: `app/dist/Symly.dmg`.

The app needs **no special entitlements** (not sandboxed, no JIT; it only spawns
Apple-signed system binaries). If a future change trips notarization, add the
entitlement in `build_release.sh`.

### Wire the site (after the DMG is released)

In the `symly-site` repo:
- Set `DOWNLOAD_URL` in `components/waitlist-form.tsx` to the GitHub Release asset URL.
- Set `GITHUB_URL` in `app/page.tsx` to `https://github.com/brandoniben/symly`.
- (Separately) wire Supabase so the email form actually persists captures.

---

## Verify the authorized install end to end

On a Mac (ideally a second one that never built it):
1. Download the DMG, open it, drag Symly to Applications.
2. It should open on first launch with no "unidentified developer" block.
3. `spctl -a -vv /Applications/Symly.app` should report `accepted, source=Notarized Developer ID`.
