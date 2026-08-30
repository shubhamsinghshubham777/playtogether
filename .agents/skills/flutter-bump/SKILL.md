---
name: flutter-bump
description: >-
  Pin the repo to a new Flutter SDK version — runs `fvm use`, syncs the Dart SDK pin in pubspec.yaml and the `flutter-version` in every GitHub workflow to match, verifies pub get, then commits and pushes. Use when the user says "bump flutter to 3.44.2", "upgrade the flutter version", "switch flutter SDK", or "/flutter-bump 3.44.2". Requires the target version as an argument.
---

# Bump the pinned Flutter version

Binds the repo to a specific Flutter SDK via FVM and keeps the **three places that must agree** in sync:
1. `.fvmrc` (written by `fvm use`)
2. The exact Dart SDK pin in `pubspec.yaml` (`environment: sdk:`)
3. Every `flutter-version:` line under `.github/workflows/`

## Steps

1. **Require the version argument.**
   If the user didn't pass one (e.g. `/flutter-bump 3.44.2`), ask for it — never guess or pick "latest". Validate it looks like `X.Y.Z`.

2. **Preflight**:
   Ensure on `main`, working tree clean (`git status --porcelain` empty), and `git pull --ff-only origin main` succeeds.

3. **Install and bind the SDK**:
   ```bash
   fvm install <version>
   fvm use <version> --skip-pub-get
   ```

4. **Sync the Dart SDK pin**:
   ```bash
   fvm dart --version
   ```
   Extract the Dart version and update `environment: sdk:` in `pubspec.yaml` to match exactly.

5. **Sync GitHub workflows & docs**:
   Update `flutter-version:` in `.github/workflows/build_windows.yaml`, `.github/workflows/build_macos.yaml`, and `.github/workflows/test.yaml`.
   Update any CI mentions in `AGENTS.md` and `CLAUDE.md`.

6. **Verify**:
   ```bash
   fvm flutter pub get
   ```

7. **Commit and push**:
   ```bash
   git add .fvmrc pubspec.yaml pubspec.lock .github/workflows/ AGENTS.md CLAUDE.md
   git commit -m "Bump Flutter to <version>"
   git push origin main
   ```
