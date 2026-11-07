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
- **Taking something out of dotfiles doesn't take it off the machine.** A removed file also goes into `home/.chezmoiremove`, and `home/dot_claude/modify_settings.json` deletes a removed Claude Code setting.

## Before you add an instruction to Claude Code

Instructions fall into 3 layers, and `home/dot_claude/CLAUDE.md` holds only one of them.

- **`home/dot_claude/CLAUDE.md` = basic policy.** It doesn't depend on any procedure or any repository. It's the relationship with Claude itself. It should still make sense even with every plugin removed.
- **Plugins such as rn = procedures.** What to do, in what order, what to keep, and where to stop.
- **Skills = knowledge of a domain.** What's the standard approach in that domain, and what to avoid.

When adding a line, decide by elimination. If it's one step of a procedure, it goes to a plugin. If it's knowledge of a domain, it goes to a skill. If it's neither, it stays in `home/dot_claude/CLAUDE.md`.
