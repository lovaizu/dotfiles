# Config files

A config file holds only what does not change while the app runs. What an app writes back on its own (plugins, hooks) is created by a chezmoi script through the app's own commands, not declared in the file. During PR #11, those parts were first kept in the repository's `claude/settings.json`, and the setup read them back from that file. Then the design was reversed. `claude/settings.json` is no longer in the repository.
