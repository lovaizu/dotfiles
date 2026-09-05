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

端末のカラースキームとフォントを両 OS で揃える。

テーマは **2 層**ある — 端末そのものの配色と、その上で動く herdr の UI テーマ。層ごとに設定を持つファイルが違う(具体的な値は下記の設定箇所を見ること)。

- **端末そのものの配色** — Win: `windows-terminal/settings.json` の `profiles.defaults.colorScheme`(スキームの実体は同ファイルの `schemes`)/ Mac: `iterm2/herdr.json` の色定義
- **herdr の UI テーマ** — `herdr/config.toml` の `[theme]`(OS 共通)

| 項目 | 値 | 設定箇所 |
|---|---|---|
| フォント | HackGen Console NF(Mac でのフォント名は `HackGenConsoleNF-Regular`) | Win: `profiles.defaults` の `font` / Mac: `iterm2/herdr.json` の `Normal Font` |

Windows Terminal では `profiles.defaults` にテーマ・フォントを置き、全プロファイル(PowerShell / Ubuntu / ClaudeCode / my など)が継承する。個別プロファイルでの上書きは行わない。

**端末は暗い配色、その上に乗る herdr の UI は明るい配色 — これは意図した組み合わせ。** 端末側は「背景色と ANSI 0–15 が実際に何色になるか」だけを決め、herdr は自分の UI(サイドバー・ペイン境界・ステータス)を自前のテーマ設定で描く。端末を暗くしても herdr は追随しない。herdr の UI を明るくしているのはワークスペースの選択状態を判別しやすくするためで、端末の明暗に自動追随させず、明るい側を明示指定している。

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
