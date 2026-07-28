---
name: release
description: Cut a PlayTogether release — analyze commits since the last release tag, bump the pubspec version accordingly, push to main, and trigger the build_installers GitHub workflow. Use when the user says "cut a release", "ship a release", "bump the version and build installers", or "/release". Optional arg overrides the computed version (e.g. "/release 0.5.0" or "/release patch").
---

# Cut a release

Bumps `version:` in pubspec.yaml, commits and pushes to `main`, and triggers the
`build_installers.yaml` workflow. **Do NOT create or push a git tag** — the
workflow's `release` job tags the commit itself as `v<version>_<run_id>` (see
`tag_name:` in `.github/workflows/build_installers.yaml`); a locally pushed tag
would be a duplicate that matches nothing.

## Steps

1. **Preflight** — abort with a clear message if any of these fail:
   - `git branch --show-current` must be `main`.
   - Working tree must be clean (`git status --porcelain` empty). If dirty, stop
     and tell the user what's uncommitted — never bundle unrelated changes into
     the bump commit.
   - `git pull --ff-only origin main` must succeed.

2. **Find the last release** — release tags look like `v0.3.0_20682763842`
   (version + workflow run id, created by CI):

   ```bash
   git tag --sort=-creatordate | head -1
   ```

   Extract the version from the tag name (strip leading `v` and trailing
   `_<run_id>`). Sanity-check it against `version:` in pubspec.yaml — they
   should match; if they don't, tell the user and ask before continuing.

3. **Decide the new version.**
   - If the user passed an explicit version (`0.5.0`) or a bump keyword
     (`patch` / `minor` / `major`), use that and skip the analysis.
   - Otherwise analyze `git log <last-tag>..HEAD --oneline`. If there are zero
     commits, abort — there is nothing to release. Read the commit subjects
     (use `git show --stat` on any that are unclear) and pick the bump using
     the 0.x scheme this app follows:
     - **minor** — any new user-facing feature or capability (new screens,
       modes, sync features, redesigns), or a breaking/behavioral change.
     - **patch** — only fixes, polish, refactors, CI/docs/chores.
     - **major** (→ 1.0.0) — never infer this; only when the user explicitly
       asks for it.
   - State the chosen version **with a one-line rationale citing the commits
     that drove the decision**, then proceed — no confirmation needed unless
     the analysis is genuinely ambiguous.

   Even when the user passed an explicit version and the bump analysis is
   skipped, still read `git log <last-tag>..HEAD --oneline` — the release
   notes in step 6 are written from it either way.

4. **Bump** — edit the `version:` line in pubspec.yaml (bare `X.Y.Z`, no
   `+build` suffix — CI's version extraction and installer names depend on
   this format).

5. **Commit and push** — message follows repo precedent, exactly:

   ```
   Bump app version to X.Y.Z
   ```

   No co-author trailers. Then `git push origin main`.

6. **Write the release notes and trigger the workflow.** Compose a Markdown
   "What's Changed" section from the commits since the last tag — user-facing
   summaries grouped by theme, not raw commit subjects. Lead with features,
   then fixes; fold internal work (CI, refactors, docs) into a single line or
   omit it. Keep it short — a handful of bullets. Include the heading, e.g.:

   ```markdown
   ## What's Changed
   - The desktop app now opens in fullscreen
   - Room names are length-limited on both client and server
   - Faster CI builds (Windows 14 min → 90 s)
   ```

   Pass it via the workflow's `release_notes` input (it lands at the top of
   the GitHub release body, above the auto-generated Downloads section):

   ```bash
   gh workflow run build_installers.yaml --ref main -f release_notes="$(cat <<'EOF'
   ## What's Changed
   - ...
   EOF
   )"
   ```

   The dispatch is async — poll until the new run appears:

   ```bash
   gh run list --workflow=build_installers.yaml --limit 1 --json url,createdAt,status
   ```

   (re-run the list command if the newest run predates the dispatch; it
   usually appears within a few seconds).

7. **Report and stop** — print the new version and the run URL. Do **not**
   watch the build (it takes 15–30 min); the workflow will create the GitHub
   release, tag, and installer artifacts on its own. Remind the user the
   release will appear at
   `https://github.com/shubhamsinghshubham777/playtogether/releases` when the
   run finishes.
