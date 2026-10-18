# Design and review

- A config file holds only what stays put. What an app writes back on its own (plugins, hooks) is created by `./setup.sh` through the app's own commands, not declared in the file. In PR #11 those parts sat in `claude/settings.json` and were read back from it, and the design was turned around.
- This repository has one user, two machines, and `./setup.sh` run by hand a few times a year. Use that to keep review findings to what affects the goal, and say it in the request when asking for a review. Never use it as a reason not to fix something: check the technical reason itself first. Both have happened: review rounds spent on findings that did not affect the goal, and in PR #11 a split of `setup.sh` turned down on that ground.
