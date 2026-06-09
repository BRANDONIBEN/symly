# Symly

A free, open-source macOS app that organizes Avid Media Composer's MXF media by
project **without ever moving, copying, or deleting a single file**.

Avid forces media into a rigid location (`Avid MediaFiles/MXF`). Instead of
shuffling folders by hand, this app makes that rigid path a **symlink** that
points at whatever named project folder you pick. Avid writes exactly where it
always has; the media lands in the folder you chose; switching projects just
repoints one link. Nothing is copied. Nothing is moved. Nothing is ever deleted
except the symlink itself.

A rebuild of the tool Brandon Iben designed/built at Final Cut in 2022, now made
free for any editor. Universal (Apple Silicon + Intel).

## The safety promise (non-negotiable)

The app (and even the spike script) only ever create or remove **symlinks**.
The engine refuses to delete anything that is not a symlink, never recursive-
deletes, and never overwrites a real folder (it relocates it with a same-volume
rename first). Your `.mxf` / `.mdb` / `.pmr` files are never touched.

## Status

Pre-release. Building in phases (the gate is a real-Avid test, below).

- ✅ **Phase 0 spike kit**: `phase0-spike/` (a safe script + checklist to prove
  Avid follows a repointed symlink on real hardware). **Run this first.**
- 🔨 **Core safety engine**: `MediaOrganizerCore/` (pure-Swift, unit-tested).
- ⏳ Volume access + drive watcher, SwiftUI app, packaging/notarization (next).

## Layout

```
phase0-spike/        spike.sh + CHECKLIST.md: validate the mechanism on a real drive
MediaOrganizerCore/  Swift Package: the headless engine + safety guard + tests
```

## Quickstart: Phase 0

```sh
cd phase0-spike
chmod +x spike.sh
./spike.sh help
```

Then follow `phase0-spike/CHECKLIST.md` on a Mac with Avid. If the import /
switch / relink test passes, the rest of the app gets built on top of the
`MediaOrganizerCore` engine.

## Design

The look and interaction are already designed: a dark, pro-editorial UI with a
magenta accent that *is* the symlink. Source of truth for the visual language is
the animated mockup in the portfolio repo
(`brandoniben_dot_com/components/media/avid-mxf-app.tsx`) and the full build plan
at `~/.claude/plans/id-like-to-take-sprightly-melody.md`.

## License

Symly is free and open source under the **Apache License 2.0**. See [LICENSE](LICENSE)
and [NOTICE](NOTICE). The license covers the source code; it is provided "AS IS",
with no warranty and no liability, as set out in sections 7 and 8 of the license.

Copyright © 2026 Brandon Iben. The "Symly" name, logo, and wordmark are trademarks
of Brandon Iben and are not granted by the license; please use a different name and
icon if you ship a fork.

Not affiliated with, endorsed by, or sponsored by Avid Technology, Inc. "Avid" and
"Media Composer" are trademarks of Avid Technology, Inc. MXF is an open SMPTE standard.
