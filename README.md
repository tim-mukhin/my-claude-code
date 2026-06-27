# my-claude-code

Personal Claude Code tweaks. Each folder is a self-contained feature — copy what
you want into `~/.claude/`. Built to be cloned by an agent ("set me up like this
repo"), not installed wholesale.

## Features

- **[tab-title/](tab-title/)** — terminal tab title with a status icon (`⋯`
  working, `⏸` needs attention, `✳` idle) plus an auto-generated session label.
  Claude Code hooks.
- **[statusline/](statusline/)** — rich status line: model, project, label,
  context %, message count, token stats, cumulative cost, and rate-limit bars
  with per-session attribution.

See each folder's README for details and install steps.

## Related

- [`my-opencode`](../my-opencode/) — same idea for OpenCode.
- [`my-copilot-cli`](../my-copilot-cli/) — same idea for GitHub Copilot CLI.
