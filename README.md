# dotfiles

Windows (WSL + Windows Terminal) と Mac (iTerm2) の端末環境を、clone して `./setup.sh` を実行するだけで再現するためのリポジトリ。両 OS で herdr の操作感(キー・テーマ・フォント)を揃える。

## キー対応表

herdr のプレフィックスは `^T`(Ctrl+T, byte `0x14`)。設定は `herdr/config.toml`(OS 共通)。

よく使う 3 操作は、プレフィックスなしの即時キーでも実行できる。端末側(Windows Terminal / iTerm2)がキーを対応するバイト列に変換して herdr に送信する。

| 操作 | herdr(送信内容) | Win キー | Mac キー |
|---|---|---|---|
| previous workspace | `^T [` (`0x14 0x5b`) | `Ctrl+Alt+[` | `⌃⌘[` |
| next workspace | `^T ]` (`0x14 0x5d`) | `Ctrl+Alt+]` | `⌃⌘]` |
| next agent | `^T u` (`0x14 0x75`) | `Ctrl+Alt+U` | `⌃⌘U` |
| 改行を送信 | `\n` (`0x0a`) | `Shift+Enter` | `⇧Enter` |
| herdr プレフィックス | `^T` (`0x14`) | `Ctrl+T`(WT の既定 `ctrl+t` を無効化してパススルー) | `⌃T`(iTerm2 は既定で奪わないため設定不要) |

- HHKB では Win の `Alt` と Mac の `⌘` が同じ物理位置にあるため、両 OS で指運びが揃う。
- プレフィックス経由の操作(`^T [` / `^T ]` / `^T u`、コピーモード `^T y`)は両 OS 共通。`⌃T` が herdr に届くことが前提。

## テーマ・フォント

| 項目 | 値 |
|---|---|
| テーマ | Gruvbox Dark |
| フォント | HackGen Console NF 13(Win: `HackGen Console NF` 13pt / Mac: `HackGenConsoleNF-Regular` 13pt) |

シェルは統一しない(Win: PowerShell / WSL bash、Mac: zsh)。herdr の起動は両 OS とも手動。

## セットアップ

### WSL (Windows)

```sh
./setup.sh
```

- herdr の設定を `~/.config/herdr/config.toml` に配置
- Windows Terminal の `settings.json` を配置(既存ファイルはバックアップ)

フォントは WSL からは Windows にインストールできないため手動。[HackGen のリリースページ](https://github.com/yuru7/HackGen/releases) から `HackGen_NF` をダウンロードし、`HackGenConsoleNF-*.ttf` を Windows にインストールする。

### Mac

```sh
./setup.sh
```

- herdr の設定を `~/.config/herdr/config.toml` に配置
- iTerm2 の Dynamic Profile を `~/Library/Application Support/iTerm2/DynamicProfiles/` に配置
- Homebrew があれば `font-hackgen-nerd` cask でフォントをインストール(なければ上記リリースページから手動)

初回のみ、iTerm2 でプロファイル「herdr」をデフォルトに設定する(手動)。
