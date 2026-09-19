# dotfiles

A repository for using the same working environment on Windows and Mac. It assumes these two environments.

- **Windows: WSL + Windows Terminal.** Work happens inside WSL; the terminal is a Windows-side app.
- **Mac: iTerm2.**

## Usage

On both OSes, this is all you need.

```sh
./setup.sh
```

`./setup.sh` prints, as it runs, what it placed where, what it backed up, and what failed.

### Fonts

The source is the same on both OSes: the [distributor's release page](https://github.com/yuru7/HackGen/releases). The name of the font to install is in the terminal's config file.

- **Windows: always manual.** You can't install from WSL to Windows.
- **Mac: `./setup.sh` installs it.**

## Before you fix a setting

Reading the config files straightforwardly makes you want to fix them, but there are 3 points that are intentional as they are.

- **The terminal uses a dark color scheme, while the herdr UI running on top of it uses a light one.** This looks inconsistent, but the light side is explicitly specified to make it easier to tell which workspace is selected. It's not meant to follow the terminal's light/dark setting.
- **The key that calls herdr from the terminal is `Ctrl+Alt` on Windows and `Ctrl+⌘` on Mac, because on the keyboard (HHKB) it's the same physical key.** This key next to the space bar works as `Alt` on Windows and `⌘` on Mac. If you "fix" the Mac side to a more "Mac-like" key, the same finger shape stops producing the same action.
- **dotfiles is the source of truth, and `./setup.sh` overwrites everything it manages, wholesale.** Any settings changed from the terminal's or herdr's UI, and any manual edits to the files they're placed in, revert to what's in dotfiles on the next run. Put anything you want to keep into dotfiles itself.

## Before you add an instruction to Claude Code

Instructions are split into 3 layers, and `claude/CLAUDE.md` holds only one of them.

- **`claude/CLAUDE.md` = basic policy.** It doesn't depend on any procedure or any repository — it's the relationship with Claude itself. It should still make sense even with every plugin removed.
- **Plugins (rn, etc.) = procedures.** What to do, in what order, what to keep, and where to stop.
- **Skills = knowledge of a domain.** What's the standard approach in that domain, and what to avoid.

When adding a line, decide by elimination: if it's one step of a procedure, it goes to a plugin; if it's knowledge of a domain, it goes to a skill. If it's neither, it stays in `claude/CLAUDE.md`.
