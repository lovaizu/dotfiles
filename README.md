# Dotfiles

A repository for using the same working environment on Windows and Mac. It assumes these two environments.

- **On Windows, Windows Subsystem for Linux (WSL) and Windows Terminal.** Work happens inside WSL. The terminal is a Windows-side app.
- **On Mac, iTerm2.**

## Usage

On both OSes, this is all you need. After changing something, `git pull` and run it again.

```sh
./setup.sh
```

It installs [mise](https://mise.jdx.dev/), and with it [chezmoi](https://www.chezmoi.io/), then applies this clone with chezmoi. mise installs each tool only at the version and the sha256 that this clone pins, so a download that differs stops the step. One failed step leaves the rest to run. Each failure says why and how to fix it, and the run ends non-zero.

### Sandbox

To work inside the Docker Sandbox, run `sb` anywhere under `~/work/<group>`. It opens herdr inside that group's sandbox, creating the sandbox on first use. When it can't start, it says why and how to fix it.

### Fonts

The source is the same on both OSes: the [distributor's release page](https://github.com/yuru7/HackGen/releases). The name of the font to install is in the terminal's config file.

- **Windows: always manual.** You can't install from WSL to Windows.
- **Mac: `./setup.sh` installs it.**

## Before you fix a setting

Reading the config files straightforwardly makes you want to fix them, but 3 points in them are intentional.

- **The key that calls herdr from the terminal is `Ctrl+Alt` on Windows and `Ctrl+⌘` on Mac, because on the keyboard, a Happy Hacking Keyboard (HHKB), it's the same physical key.** This key next to the space bar works as `Alt` on Windows and `⌘` on Mac. If you "fix" the Mac side to a more "Mac-like" key, the same finger shape stops producing the same action.
- **dotfiles is the source of truth.** On the next apply, chezmoi asks about a placed file that changed from an app's UI or by hand, and overwriting it brings back what's in dotfiles. Put anything you want to keep into dotfiles itself. There are two exceptions. Claude Code's `settings.json` gets only the keys kept here. What Claude Code and herdr write into it stays. `./setup.sh` copies Windows Terminal's settings over without asking.
- **Taking something out of dotfiles doesn't always take it off the machine.** Each kind of thing leaves in its own way:
  - A file leaves when `home/.chezmoiremove` names it.
  - A Claude Code setting leaves when `home/dot_claude/modify_settings.json` deletes it. A hook also has a script, which leaves as a file.
  - A plugin of Claude Code leaves when `home/run_after_plugins.sh.tmpl` lists it.
  - A tool of mise leaves on its own. `./setup.sh` deletes each version that no config of mise on the machine names. mise knows a config, such as the `mise.toml` of a project, once it has loaded it, and forgets it once someone deletes the file.

## Before you add an instruction to Claude Code

Instructions fall into 3 layers by what they apply to, and `home/dot_claude/CLAUDE.md` holds only one of them.

- **General: `home/dot_claude/CLAUDE.md`.** It holds for any kind of work: deciding, reporting, what not to destroy, and techniques that still say something without the words of the domain they came from.
- **Process: plugins such as rn.** The order of steps, and where to stop. It means nothing outside its workflow.
- **Specialized: skills.** What good work looks like inside one craft. It means nothing without the words of that craft.

To tell general from specialized, restate the rule without the words of the domain it came from. If it still says something, it's general. "Keep the starting state, the action, and the expected result apart" survives. "Mock the module boundary" doesn't.

A general rule still stays out of `home/dot_claude/CLAUDE.md` when a line there already implies it. Every conversation reads that file, so its value is its shortness. Wanting a rule to apply everywhere is about reach, not about layer. If a skill doesn't fire when it should, fix how it's invoked.
