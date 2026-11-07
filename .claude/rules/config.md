# Config files

A config file holds only what doesn't change while the app runs. A chezmoi script creates what an app writes back on its own, such as plugins and hooks, through the app's own commands. The file doesn't declare it. During PR #11, those parts were first kept in the repository's `claude/settings.json`, and the setup read them back from that file. Then PR #11 reversed the design. `claude/settings.json` is no longer in the repository.
