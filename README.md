# agent-plugins

> **Research Preview** — This is an experimental prototype. Expect breaking
> changes and rough edges. Not security-hardened; designed for local use only.
> Feedback welcome via [GitHub Issues](https://github.com/shlomihod/agent-plugins/issues).

Shlomi Hod's library of AI agent plugins.

## Install

Pick a plugin from the list below and substitute its name for `<name>`.

**Claude Code** — works for every plugin here:

```text
/plugin marketplace add shlomihod/agent-plugins
/plugin install <name>@agent-plugins
```

**Codex / Hermes** — for the standalone `SKILL.md` skills in this repo
(`drive-claude-code-with-tmux`, `terms-watch`; not `ezra`, which is Claude Code only):

```text
# Codex — drop the skill folder into your skills path, then invoke with $<name>
cp -r plugins/<name>/skills/<name> ~/.agents/skills/

# Hermes — install the skill by its raw SKILL.md URL
hermes skills install https://raw.githubusercontent.com/shlomihod/agent-plugins/main/plugins/<name>/skills/<name>/SKILL.md
```

Some skills have prerequisites (e.g. `drive-claude-code-with-tmux` needs `tmux`,
with `perl` recommended for precise sub-second polling); see the plugin's folder.

## Plugins

- **[drive-claude-code-with-tmux](plugins/drive-claude-code-with-tmux)** — drive a Claude Code instance with tmux: launch it, send prompts, approve its permission prompts step by step, read what it did, and clean up.
- **[ezra](https://ezra.tools)** — AI document review with tracked changes and comments. Sourced from [`shlomihod/ezra`](https://github.com/shlomihod/ezra).
- **[terms-watch](plugins/terms-watch)** — query [Terms Watch](https://termswatch.io/) for tracked changes to Terms of Service and Privacy Policies across major platforms: recent changes, diffs, and summaries over a paginated JSON API (no auth).

## License

[MIT](LICENSE)
