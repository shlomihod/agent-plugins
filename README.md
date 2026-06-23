# agent-plugins

> **Research Preview** — This is an experimental prototype. Expect breaking
> changes and rough edges. Not security-hardened; designed for local use only.
> Feedback welcome via [GitHub Issues](https://github.com/shlomihod/agent-plugins/issues).

Shlomi Hod's library of AI agent plugins.

## Plugins

- **[drive-claude-code-with-tmux](plugins/drive-claude-code-with-tmux)** — drive a Claude Code instance with tmux: launch it, send prompts, approve its permission prompts step by step, read what it did, and clean up.
- **[ezra](https://ezra.tools)** — AI document review with tracked changes and comments. Sourced from [`shlomihod/ezra`](https://github.com/shlomihod/ezra).

## Install

**Claude Code**

```text
/plugin marketplace add shlomihod/agent-plugins
/plugin install drive-claude-code-with-tmux@agent-plugins
/plugin install ezra@agent-plugins
```

**Hermes**

```text
hermes skills install shlomihod/agent-plugins/plugins/drive-claude-code-with-tmux/skills/drive-claude-code-with-tmux
```

Requires `tmux` (`perl` recommended, for precise sub-second polling).

## License

[MIT](LICENSE)
