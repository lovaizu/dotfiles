# Config files

A config file holds only what stays put. What an app writes back on its own (plugins, hooks) is created by `./setup.sh` through the app's own commands, not declared in the file. In PR #11 those parts sat in `claude/settings.json` and were read back from it, and the design was turned around.
