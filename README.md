# Calorie tracker project kit

Starter layout for a personal iOS calorie tracker. Nothing here is app code yet.

```
CLAUDE.md                  rules for Claude Code in this repo
docs/                      spec, architecture, OpenAI sign-in notes, open questions
.claude/skills/            four Swift skills (MIT, from Paul Hudson and Daniel Eden)
claude-project/
  instructions.md          paste into a claude.ai Project's instructions
```

## Use it as a claude.ai Project
1. Create a Project, paste `claude-project/instructions.md` into its instructions.
2. Upload the four files in `docs/` as project knowledge.

## Use it with Claude Code
1. Copy this folder's contents into the repo root (`git init` first).
2. `.claude/skills/` loads automatically; `CLAUDE.md` is read on startup.
3. Start with Phase 0 in `docs/architecture.md`.

## Skill sources
- swiftui-pro, swift-concurrency-pro, swiftdata-pro: github.com/twostraws (Paul Hudson), MIT
- swiftui-gotchas: github.com/daneden/agent-skills, MIT
