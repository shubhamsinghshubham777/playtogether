# AGENTS.md

This repository also supports Codex. The complete project guidance is kept in
`CLAUDE.md` so Claude Code and Codex share one source of truth; read that file
before making changes.

Codex project skills are available under `.codex/skills/`. They mirror the
Claude Code skills under `.claude/skills/`:

- `release` — cut a stable or pre-release and trigger installer builds.
- `flutter-bump` — update the pinned Flutter/Dart SDK versions and workflows.

Follow the skill whose description matches the user's request, including its
preflight, verification, and git-operation rules. Keep both instruction
directories in sync when changing repository guidance.
