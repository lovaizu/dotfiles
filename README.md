# dotfiles

Windows (WSL + Windows Terminal) と Mac (iTerm2) の端末環境を、clone して `./setup.sh` を実行するだけで再現するためのリポジトリ。両 OS で herdr のキー操作と、端末(Windows Terminal / iTerm2)のテーマ・フォントを揃える。

シェルは統一しない(Win: PowerShell / WSL bash、Mac: zsh)。herdr の起動は両 OS とも手動。

## キー対応表

herdr のプレフィックスは `^T`(Ctrl+T, byte `0x14`)。設定は `herdr/config.toml`(OS 共通)。

下表は、よく使う 3 操作の即時切替(プレフィックスなしで実行できるキー)に加え、改行の送信と herdr プレフィックスのパススルーをまとめたもの。即時切替と改行送信は、端末側(Windows Terminal / iTerm2)がキーを対応するバイト列に変換して herdr に送信する。プレフィックスは端末が奪わず、そのまま herdr に届く。

| 操作 | herdr(送信内容) | Win キー | Mac キー |
|---|---|---|---|
| previous workspace | `^T [` (`0x14 0x5b`) | `Ctrl+Alt+[` | `⌃⌘[` |
| next workspace | `^T ]` (`0x14 0x5d`) | `Ctrl+Alt+]` | `⌃⌘]` |
| next agent | `^T u` (`0x14 0x75`) | `Ctrl+Alt+U` | `⌃⌘U` |
| 改行を送信 | `\n` (`0x0a`) | `Shift+Enter` | `⇧Enter` |
| herdr プレフィックス | `^T` (`0x14`) | `Ctrl+T`(WT の既定 `ctrl+t` を無効化してパススルー) | `⌃T`(iTerm2 は既定で奪わないため設定不要) |

- HHKB では Win の `Alt` と Mac の `⌘` が同じ物理位置にあるため、両 OS で指運びが揃う。
- プレフィックス経由の操作(`^T [` / `^T ]` / `^T u`、コピーモード `^T y`)は両 OS 共通。プレフィックス `^T` が herdr に届くことが前提。

## テーマ・フォント

端末(Windows Terminal / iTerm2)のカラースキームとフォントを両 OS で揃える。

| 項目 | 値 |
|---|---|
| テーマ(端末のカラースキーム) | Gruvbox Dark(背景 `#282828` / 前景 `#EBDBB2`) |
| フォント | HackGen Console NF 13(Win: `HackGen Console NF` 13pt / Mac: `HackGenConsoleNF-Regular` 13pt) |
| herdr の UI テーマ | `gruvbox`(dark) |

Windows Terminal では `profiles.defaults` にこの値を置き、全プロファイル(PowerShell / Ubuntu / ClaudeCode / my など)が継承する。個別プロファイルでのテーマ・フォント上書きは行わない。

テーマは 2 か所にあり、両方を暗い配色で揃える必要がある。端末(Windows Terminal / iTerm2)側は「端末そのものの配色」— 背景色と ANSI 0–15 が実際に何色になるか。herdr 側は `herdr/config.toml` の `[theme]` で「herdr が自分の UI(サイドバー・ペイン境界・ステータス)を描くときの配色」を決める。端末だけ暗くしても herdr の UI は追随しないため、`name = "gruvbox"` を明示している(`auto_switch = false`)。

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

#### 初回のみ: herdr プロファイルをデフォルトにする(必須・手動)

キーマッピングは Dynamic Profile「herdr」に入っているため、**そのプロファイルで開いたウィンドウにしか効かない**。
デフォルトにしていないと、通常のウィンドウでは `⌃⌘[` などが素通りして herdr のワークスペース切り替えが動かない。

1. iTerm2 の Settings(`⌘,`)→ Profiles → 左の一覧から **herdr** を選択
2. 下部の **Other Actions...** → **Set as Default**
3. **新しいウィンドウを開く**(`⌘N`)。既存のウィンドウは開いた時のプロファイルを保持するため、設定しても切り替わらない

`./setup.sh` は herdr がデフォルトプロファイルでない場合に警告を出す。
