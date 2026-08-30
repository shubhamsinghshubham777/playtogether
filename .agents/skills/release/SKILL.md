---
name: release
description: >-
  Cut a SyncTogether release or pre-release — analyze commits since the last release tag, bump the pubspec version accordingly, push to main, and trigger the build_installers GitHub workflow. Use when the user says "cut a release", "ship a release", "cut a pre-release", "bump the version and build installers", or "/release". Optional arg overrides the computed version (e.g. "/release 0.5.0" or "/release patch"); a "pre" arg (alone or combined, e.g. "/release pre" or "/release pre minor") publishes it as a GitHub pre-release.
---

# Cut a release

Bumps `version:` in `pubspec.yaml`, commits and pushes to `main`, and triggers the `build_installers.yaml` workflow.

> [!IMPORTANT]
> **Do NOT create or push a git tag locally** — the workflow's `release` job tags the commit itself as `v<version>_<run_id>`.

## Steps

1. **Preflight**:
   - `git branch --show-current` must be `main`.
   - Working tree must be clean (`git status --porcelain` empty).
   - `git pull --ff-only origin main` must succeed.

2. **Find last release tag**:
   ```bash
   git tag --sort=-creatordate | head -1
   ```
   Extract the version (e.g. `0.4.0` from `v0.4.0_123456`).

3. **Decide new version**:
   - If argument passed (e.g. `0.5.0` or `patch`/`minor`/`major`), use that.
   - Otherwise, analyze `git log <last-tag>..HEAD --oneline`:
     - **minor**: New user-facing feature/capability or behavioral change.
     - **patch**: Bug fixes, polish, refactors, docs, chores.
     - **pre-release (`pre`)**: Default to patch unless commits clearly warrant minor.

4. **Bump version**:
   Edit `version:` in `pubspec.yaml` (bare `X.Y.Z`).

5. **Commit and push**:
   ```bash
   git add pubspec.yaml
   git commit -m "Bump app version to <version>"
   git push origin main
   ```

6. **Trigger CI workflow**:
   Compose release notes from commit history:
   ```bash
   gh workflow run build_installers.yaml --ref main -f release_notes="$(cat <<'EOF'
   ## What's Changed
   - Feature 1
   - Fix 2
   EOF
   )"
   ```
   *(For a pre-release, append `-f prerelease=true`)*

7. **Monitor dispatch**:
   ```bash
   gh run list --workflow=build_installers.yaml --limit 1 --json url,createdAt,status
   ```
   Report the workflow run URL and new version to the user.
