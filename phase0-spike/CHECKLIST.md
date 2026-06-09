# Phase 0: Real-Avid validation checklist

**Goal:** prove that Avid Media Composer follows a repointed `Avid MediaFiles/MXF`
symlink transparently, *before* we build the app. This is the one assumption the
whole product rests on. ~30 minutes.

**You will not touch any real project's media.** This test uses fresh, empty test
projects. The `spike.sh` script only ever creates or removes symlinks.

**Prereqs**
- A Mac with Avid Media Composer installed.
- A drive to test on (the external/working drive you actually edit from is ideal,
  because the real question is how Avid behaves on *that* hardware/filesystem).
- The `spike.sh` script in this folder (`chmod +x spike.sh` if needed).

In the steps below, replace `DRIVE` with your drive root, e.g.
`/Volumes/MediaDrive` (or a test folder on it like `/Volumes/MediaDrive/spike`).

---

## A. Set up two empty test projects

```sh
./spike.sh setup "DRIVE/mxf-phase0"            # dry run, shows what it will do
./spike.sh setup "DRIVE/mxf-phase0" --apply    # creates it
./spike.sh status "DRIVE/mxf-phase0"
```

This makes:
- `DRIVE/mxf-phase0/Avid MediaFiles/MXF`  → a **symlink** to ProjectA's MXF
- `DRIVE/mxf-phase0/MediaOrganizer Projects/ProjectA/MXF/1/` (with stand-in `.mdb`/`.pmr`)
- `…/ProjectB/MXF/1/`

> The stand-in `.mdb`/`.pmr` files are deleted-and-rebuilt by Avid; that's
> expected. The point is to watch whether Avid writes into, and reads back
> from, the linked location.

- [ ] `status` reports `Avid MediaFiles/MXF: symlink → …/ProjectA/MXF`

## B. Import into Project A

1. [ ] Launch Media Composer. Point its media drive / capture-and-import target at
       `DRIVE/mxf-phase0` (so it uses `DRIVE/mxf-phase0/Avid MediaFiles`).
2. [ ] Import or AMA-consolidate a short clip.
3. [ ] In Finder, confirm the new `.mxf` (and a freshly built `msmMMOB.mdb` /
       `msmFMID.pmr`) landed under
       `DRIVE/mxf-phase0/MediaOrganizer Projects/ProjectA/MXF/…`
       (i.e. Avid wrote **through** the symlink into the real ProjectA folder).
4. [ ] Quit Media Composer.

- [ ] **Pass:** the media physically lives in ProjectA, not anywhere else.

## C. Switch to Project B

```sh
./spike.sh link "DRIVE/mxf-phase0" ProjectB           # dry run
./spike.sh link "DRIVE/mxf-phase0" ProjectB --apply
./spike.sh status "DRIVE/mxf-phase0"
```

1. [ ] Relaunch Media Composer.
2. [ ] Project A's media should now read as **offline / media not found** (its
       files are no longer under the linked location).
3. [ ] Import a *different* clip. Confirm it lands under `…/ProjectB/MXF/…`.
4. [ ] Quit.

## D. Switch back to Project A and relink

```sh
./spike.sh link "DRIVE/mxf-phase0" ProjectA --apply
```

1. [ ] Relaunch Media Composer.
2. [ ] Project A's media should come back **online** automatically (Avid finds it
       again at the linked location), or relink cleanly with one prompt.

- [ ] **Pass:** A goes offline when switched away, comes back online when switched
      back: no copying, no moving of the real files, just the link repointed.

## E. (Optional) Adopt an existing real MXF

Only if you want to test bringing a drive that *already* has media under
`Avid MediaFiles/MXF` into the system:

```sh
./spike.sh status "DRIVE/existing"                 # shows "REAL FOLDER (not yet adopted)"
./spike.sh adopt  "DRIVE/existing" Show1            # dry run
./spike.sh adopt  "DRIVE/existing" Show1 --apply    # same-volume move, then link
```

- [ ] The media moved into `…/MediaOrganizer Projects/Show1/MXF` (instant, no copy)
      and `Avid MediaFiles/MXF` is now a symlink to it.
- [ ] Media Composer still finds the media at launch.

## F. Clean up

```sh
./spike.sh teardown "DRIVE/mxf-phase0" --apply
```

---

## Record the result

- macOS version: ____________  Media Composer version: ____________
- Drive type / filesystem (APFS / HFS+ / NTFS-for-Mac / SMB / NEXIS): ____________
- B (import through link): ☐ pass ☐ fail. Notes: ____________
- C (switch away → offline + import to B): ☐ pass ☐ fail. Notes: ____________
- D (switch back → relink/online): ☐ pass ☐ fail. Notes: ____________
- Anything weird (extra prompts, slow scans, DB rebuilds, dupes): ____________

**If B, C and D all pass, the mechanism is sound and the app is worth building.**
**If any fail,** capture the exact behavior (screens, Finder state). That tells
us whether it's a granularity problem (symlink the numbered folder instead?), a
filesystem problem, or a hard "Avid won't follow it on this setup" answer.
