# AGENTS.md

This repository supports Antigravity, Claude Code, and Codex. The complete project guidance is kept in
`CLAUDE.md` so all AI assistants share one source of truth; read that file
before making changes.

Project skills (`release`, `flutter-bump`) are available under `.claude/skills/`, `.codex/skills/`, and mapped for Antigravity via `.agents/skills.json`:

- `release` — cut a stable or pre-release and trigger installer builds.
- `flutter-bump` — update the pinned Flutter/Dart SDK versions and workflows.

Follow the skill whose description matches the user's request, including its
preflight, verification, and git-operation rules. Keep instruction
directories in sync when changing repository guidance.
