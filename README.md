# Symly

A free, open-source macOS app that organizes Avid Media Composer's MXF media by
project. It repoints **a single symlink**, so your media files stay exactly where they are.

Avid forces media into a rigid location (`Avid MediaFiles/MXF`). Instead of
shuffling folders by hand, Symly makes that rigid path a **symlink** that points
at whatever media folder you pick. Avid writes exactly where it always has; the
media lands in the folder you chose; switching projects just repoints one link.
The only thing Symly ever creates or removes is that symlink.

Universal (Apple Silicon + Intel). Requires macOS 13 Ventura or later.

## Install

Download the latest signed and notarized build from
[getsymly.app](https://getsymly.app) or the
[Releases page](https://github.com/brandoniben/symly/releases/latest). Open the
DMG and drag Symly to your Applications folder. It opens with no Gatekeeper
warning.

## How it works

1. Pick the drive your Avid media lives on.
2. Create a media folder, or point Symly at an existing one.
3. Switch your active Avid project in one click. Symly repoints the
   `Avid MediaFiles/MXF` symlink to the media folder you chose.

Works on APFS, Mac OS Extended, and exFAT.

## The safety promise (non-negotiable)

Symly only ever creates or removes **symlinks**. The engine refuses to delete
anything that is not a symlink, never recursive-deletes, and never overwrites a
real folder (it relocates it with a same-volume rename first). Your `.mxf`,
`.mdb`, and `.pmr` files are never touched. Each project keeps its own Avid
database pair, so Media Composer relinks cleanly.

See [RISKS.md](RISKS.md) for the full failure-mode analysis and how the engine
guards against each one.

## Build from source

```sh
# the engine: pure Swift, unit-tested
cd SymlyCore && swift test

# the app
cd app && swift build && ./make-app.sh debug   # produces dist/Symly.app
```

- `SymlyCore/` is the headless engine plus its safety guard and tests.
- `app/` is the SwiftUI app built on top of it.
- `phase0-spike/spike.sh` validates the mechanism on a real Avid drive.

## License

Symly is free and open source under the **Apache License 2.0**. See [LICENSE](LICENSE)
and [NOTICE](NOTICE). The license covers the source code; it is provided "AS IS",
with no warranty and no liability, as set out in sections 7 and 8 of the license.

Copyright © 2026 Brandon Iben. The "Symly" name, logo, and wordmark are trademarks
of Brandon Iben and are not granted by the license; please use a different name and
icon if you ship a fork.

Not affiliated with, endorsed by, or sponsored by Avid Technology, Inc. "Avid" and
"Media Composer" are trademarks of Avid Technology, Inc. MXF is an open SMPTE standard.
