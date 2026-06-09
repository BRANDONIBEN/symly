# Before pushing / open-sourcing / shipping a download — open items

Brandon asked to be reminded of these before we push the public GitHub repo or
ship a download (noted 2026-06-08). Raise them first, don't push past them.

1. **Contact email.** RESOLVED 2026-06-09: confirmed `symly@brandoniben.com` (a
   domain Brandon owns). Applied in the app Help screen (ContentView) and the site
   Terms/Privacy. The old `symly@lettersagency.com` is fully removed from both.

2. **Uncommitted release edits.** The "released personally under Brandon Iben,
   Apache 2.0" changes are not committed yet (LICENSE, NOTICE, README,
   make-app.sh, ContentView terms here; site footers + Terms in the site repo).
   Review the diff and commit before any push.

Also gating a public **download**: the app must be signed + notarized first
(individual Apple Developer ID under Brandon Iben), then a `build_release.sh`
(codesign + hardened runtime, DMG, notarytool submit, staple, spctl verify). See
README.
