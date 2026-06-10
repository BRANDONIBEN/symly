# Symly: how a symlink can go wrong, and what we do about it

Symly rests on one mechanism: `<drive>/Avid MediaFiles/MXF` is a symlink the app
repoints at `<drive>/Symly Media/<project>/MXF`. Avid reads and writes through
it; switching projects repoints the one link. The safety promise is that Symly
only ever creates or removes **symlinks** and relocates real folders by an
instant **same-volume rename**, never copying or deleting media.

This file is the catalog of every way that link can go wrong, what state it
leaves, and how Symly handles it. Status legend: **[fixed]** mitigated in the
engine with a test; **[app]** surfaced as a guard/advisory in the UI;
**[validate]** environmental, proven by the Phase 0 spike, not something code can
force.

## Resolution failures (the link points at nothing, or the wrong place)

- **Drive unplugged / dangling link.** `LinkValidator.targetResolves` reports it;
  Avid reads offline. Reconnect restores it. Not preventable, only reported.
- **Drive remounts at a different path** (another Mac, another bay, or macOS
  appends ` 1` because the name was briefly taken). **[fixed]** Link targets are
  stored **relative** to the link's own directory, so they carry no mount point
  and keep resolving after any remount. Test: `testLinkIsRelativeAndSurvivesRemount`
  moves the whole root and confirms the link still resolves.
- **Target renamed/deleted in Finder.** Renaming `Symly Media` or a project
  folder outside the app breaks the link silently. The in-app rename
  (`planRenameProjectsFolder`) repoints correctly; a Finder rename does not. The
  app reads as "missing / reconnect" and re-linking fixes it.
- **Active project misread on a case-insensitive or accented drive.** **[fixed]**
  Active-project matching is by path component, ignoring case and Unicode normal
  form (`Workspace.sameComponent`). Test: `testActiveProjectMatchesCaseInsensitively`.

## Clobber risks (something real sits where the link goes) — all [fixed]

- **A real MXF folder is already there** (Avid wrote directly): refused with
  `wouldOverwriteRealDirectory`; must be adopted (relocated) first.
- **A real file at the path:** `notADirectory`, blocked.
- **Removing/replacing a non-symlink would delete media:** the I1 invariant.
  `removeSymlink` asserts `isSymlink` first; the atomic repoint refuses to replace
  anything that is not a symlink (rename of a symlink cannot clobber a directory).
  Tests: `testRemoveSymlinkGuardRefusesRealDirectory`, `testRepointRefusesRealDirectory`.

## The relocate under adoption/rename — all [fixed]

- **Cross-volume "move" silently copies bytes:** blocked by `assertSameVolume`
  (compares device ids), so a relocate is always a metadata rename.
- **Destination already exists:** `destinationExists`, refuses to merge.

## Atomicity and interruption

- **Crash/yank mid-switch leaving the path with no link.** **[fixed]** A switch is
  an **atomic repoint**: a temp link is written beside the rigid path and renamed
  over the old one, so the path is always either the old link or the new one,
  never absent.
- **Editor deletes the MXF link or the whole Avid MediaFiles folder.** **[fixed]**
  Deleting a symlink never touches media. The app reads `missing` and offers
  reconnect; re-linking recreates the parent folder. Tests:
  `testDeletingLinkLeavesMediaAndAllowsRelink`,
  `testDeletingAvidMediaFilesFolderAllowsRelink`.
- **Launch -> switch -> quit -> relaunch.** **[fixed]** The on-disk link is the
  only source of truth; a fresh launch re-derives the active project from it. Test:
  `testRelaunchRederivesActiveProjectFromDisk`.
- **Name traversal** (`..`, `/`, empty) building an escaping path. **[fixed]**
  `validName` is applied to every name that becomes a folder. Test:
  `testInvalidProjectNameThrows`.

## Filesystem support (the volume can't do what we need)

- **Filesystem genuinely can't store a symlink.** **[fixed/app]**
  `checkVolumeSupport` probes the drive (create + read back + remove a temp link)
  and reports `noSymlinks` only when the link truly fails (e.g. some SMB/NAS
  shares). Test: `testVolumeSupportOKOnTempVolume` (positive path).
  NOTE: exFAT and FAT **do** support symlinks on macOS (verified on real exFAT
  hardware), so they are NOT blocked. The old "exFAT can't do symlinks" line was a
  Windows fact wrongly applied; corrected. The one exFAT gap is the deny-delete
  folder lock (no ACLs on exFAT), which is hidden in Settings on those drives.
- **Read-only / locked mount or missing write permission.** **[fixed/app]**
  `checkVolumeSupport` returns `notWritable`.
- **SMB / NAS / Avid NEXIS: symlink support varies by server.** **[validate]**
  The probe catches servers that reject or silently drop symlinks; anything
  subtler must be proven on the real setup with the Phase 0 spike.

## Avid's own behavior — the Phase 0 gate [validate]

The one risk that is **not** a code fix: if Avid stores the *resolved* path
(`realpath`) of the media location in its `.mdb` / `.pmr` / media database, then
repointing the link leaves Avid's database pointing at the old resolved path, so
media reads **offline even though the link is correct**. The relative-link change
helps (the resolved path stays stable across remounts), but whether Avid follows
a repointed link transparently is exactly what `phase0-spike/CHECKLIST.md` exists
to prove on real hardware. If it fails, the fallback is to symlink at a different
granularity (e.g. the numbered subfolder) or rethink the mechanism. **Do not ship
past Phase 0 until import / switch-away / switch-back all pass on a real Avid drive.**

## Advisory (the app warns, never blocks) [app]

- **Switching while Avid is open.** Doable, not recommended. The app shows a
  non-blocking advisory (quit Avid for a clean switch) and lets the user proceed;
  the common recovery is to relaunch Symly, re-establish the right link, and keep
  working. Atomic repoint makes this safer (Avid's open handles follow the inode).
- **Projects folder under a cloud-synced path** (iCloud Drive, Dropbox, Google
  Drive). Sync tools can follow the link and duplicate or corrupt media. The app
  warns if the chosen root looks cloud-synced.

## Out of our hands (document, don't fix)

- Backup tools (Time Machine, Carbon Copy) following the link and duplicating the
  media tree; `cp`/`rsync` without `-P` flattening it; Finder zip dereferencing.
  These are general symlink facts; the System Requirements page tells users to keep
  the projects folder off sync/backup-followed locations.
