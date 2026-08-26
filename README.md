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

端末のカラースキームとフォントを両 OS で揃える。テーマは **3 層**あり、層ごとに設定箇所も値も違う。

| 項目 | 値 | 設定箇所 |
|---|---|---|
| 端末そのものの配色 | Gruvbox Dark(背景 `#282828` / 前景 `#EBDBB2`) | Win: `windows-terminal/settings.json` の `profiles.defaults.colorScheme` / Mac: `iterm2/herdr.json` の色定義 |
| herdr の UI テーマ | `gruvbox-light` | `herdr/config.toml` の `[theme] name` |
| Claude Code の UI テーマ | `light`(組み込み) | `claude/settings.json` の `theme` |
| フォント | HackGen Console NF 13(Win: `HackGen Console NF` 13pt / Mac: `HackGenConsoleNF-Regular` 13pt) | Win: `profiles.defaults` / Mac: `iterm2/herdr.json` |

Windows Terminal では `profiles.defaults` にテーマ・フォントを置き、全プロファイル(PowerShell / Ubuntu / ClaudeCode / my など)が継承する。個別プロファイルでの上書きは行わない。

**端末が暗く、その上に乗る UI が明るいのは意図した組み合わせ。** 端末側は「背景色と ANSI 0–15 が実際に何色になるか」だけを決め、herdr と Claude Code は自分の UI(herdr ならサイドバー・ペイン境界・ステータス)を自前のテーマ設定で描く。端末を暗くしても両者は追随しない。herdr を light にしているのはワークスペースの選択状態を判別しやすくするためで、`auto_switch = false` を置いて `name = "gruvbox-light"` を明示している。Claude Code も同じ理由で組み込みの `light` を使う — カスタムテーマだと、テーマ名だけが他 PC に渡って実体が無いときに警告なく組み込みへフォールバックするため、組み込みテーマだけで揃えている。

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
