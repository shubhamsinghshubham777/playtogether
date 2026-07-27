---
name: flutter-bump
description: Pin the repo to a new Flutter SDK version — runs `fvm use`, syncs the Dart SDK pin in pubspec.yaml and the `flutter-version` in every GitHub workflow to match, verifies pub get, then commits and pushes. Use when the user says "bump flutter to 3.44.2", "upgrade the flutter version", "switch flutter SDK", or "/flutter-bump 3.44.2". Requires the target version as an argument.
---

# Bump the pinned Flutter version

Binds the repo to a specific Flutter SDK via fvm and keeps the **three places
that must agree** in sync: `.fvmrc` (written by `fvm use`), the exact Dart SDK
pin in pubspec.yaml (`environment: sdk:`), and every `flutter-version:` line
under `.github/workflows/`. Missing any one of them breaks either local builds
or CI.

## Steps

1. **Require the version argument.** If the user didn't pass one (e.g.
   `/flutter-bump 3.44.2`), ask for it — never guess or pick "latest".
   Validate it looks like `X.Y.Z`.

2. **Preflight** — same rules as `/release`: on `main`, working tree clean
   (untracked files are fine; stop on modified/staged files and tell the user),
   `git pull --ff-only origin main` succeeds.

3. **Install and bind the SDK** (install first — `fvm use` prompts
   interactively when the version isn't cached, which hangs a non-interactive
   shell):

   ```bash
   fvm install <version>
   fvm use <version> --skip-pub-get
   ```

   This rewrites `.fvmrc` (tracked) and the gitignored `.fvm/` symlinks. If
   fvm reports the version doesn't exist, stop and tell the user.

4. **Sync the Dart SDK pin.** Get the Dart version bundled with the new
   Flutter:

   ```bash
   fvm dart --version
   ```

   (outputs e.g. `Dart SDK version: 3.12.2 (stable) …`). Set
   `environment: sdk:` in pubspec.yaml to exactly that version — this repo
   pins it exactly (no `^`/ranges, same convention as its dependencies), and
   the dot-shorthand syntax used throughout the code needs the matching SDK.

5. **Sync the workflows.** Update **every** `flutter-version:` line in
   `.github/workflows/*.yaml` to the new version (quoted, e.g.
   `flutter-version: '3.44.2'`). Currently that's `build_windows.yaml` and
   `build_macos.yaml` — `build_installers.yaml` calls those two as reusable
   workflows and pins nothing itself — but grep rather than assume:

   ```bash
   grep -rn 'flutter-version' .github/workflows/
   ```

   After editing, re-run the grep and confirm every hit shows the new version.

   Also update CLAUDE.md — it documents the CI Flutter version in prose
   (currently "CI uses Flutter 3.38.1"). Find it with
   `grep -n 'Flutter [0-9]' CLAUDE.md` and update every mention.

6. **Verify** — the whole point of the exact pins is that this must resolve:

   ```bash
   fvm flutter pub get
   ```

   If it fails, report the error and do **not** commit — leave the changes in
   the working tree for the user to inspect.

7. **Commit and push** — include `.fvmrc`, pubspec.yaml, pubspec.lock (if it
   changed), CLAUDE.md, and the workflow files. Message, exactly:

   ```
   Bump Flutter to <version>
   ```

   No co-author trailers. Then `git push origin main`.

8. **Report** — state the new Flutter version, the Dart SDK it pins, and which
   files changed. Note that CI picks up the new version on its next run; do
   not trigger any workflow (that's `/release`'s job).
