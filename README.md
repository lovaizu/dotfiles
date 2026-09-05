# dotfiles

Windows (WSL + Windows Terminal) と Mac (iTerm2) の端末環境を、clone して `./setup.sh` を実行するだけで再現するためのリポジトリ。両 OS で herdr のキー操作と、端末(Windows Terminal / iTerm2)のテーマ・フォントを揃える。

シェルは統一しない(Win: PowerShell / WSL bash、Mac: zsh)。herdr の起動は両 OS とも手動。

この README は**何ができるか / なぜそうなっているか / 手でやるしかない箇所**だけを書く。具体的な設定値(キーに割り当てたバイト列、色、フォント名とサイズ、テーマ名)は設定ファイルの側にしか置かない — 2 か所に書くと、値を変えるたびに両方を直すことになる。値を知りたいときは、各節が指す設定ファイルを見ること。

## キー対応表

herdr のプレフィックスは `Ctrl+T`(Mac は `⌃T`)。herdr 側のキー割り当ては `herdr/config.toml` の `[keys]`(OS 共通)。

下表は、よく使う 3 操作の即時切替(プレフィックスなしで実行できるキー)に加え、改行の送信と herdr プレフィックスのパススルーをまとめたもの。即時切替と改行送信は、端末側がキーを herdr の待つバイト列に変換して送る — その変換は Win: `windows-terminal/settings.json` の `actions`(`sendInput`)と `keybindings` / Mac: `iterm2/herdr.json` の `Keyboard Map` が持つ。

| 操作 | Win キー | Mac キー |
|---|---|---|
| previous workspace | `Ctrl+Alt+[` | `⌃⌘[` |
| next workspace | `Ctrl+Alt+]` | `⌃⌘]` |
| next agent | `Ctrl+Alt+U` | `⌃⌘U` |
| 改行を送信 | `Shift+Enter` | `⇧Enter` |
| herdr プレフィックス | `Ctrl+T` | `⌃T` |

- **両 OS で指運びが揃うのが狙い。** HHKB では Win の `Alt` と Mac の `⌘` が同じ物理位置にあるので、同じ指の形で同じ操作になる。
- **プレフィックスが端末に横取りされず herdr に届くことが前提。** Windows Terminal は `ctrl+t` を既定で使うので `keybindings` で無効化してパススルーさせている(`"id": null`)。iTerm2 は既定で奪わないため設定は要らない。
- プレフィックス経由の操作(コピーモードなど)は端末を経由しないので両 OS 共通。何がどのキーに割り当たっているかは `herdr/config.toml` の `[keys]` を見ること。

## テーマ・フォント

端末のカラースキームとフォントを両 OS で揃える。

テーマは **2 層**ある — 端末そのものの配色と、その上で動く herdr の UI テーマ。層ごとに設定を持つファイルが違う(具体的な値は下記の設定箇所を見ること)。

- **端末そのものの配色** — Win: `windows-terminal/settings.json` の `profiles.defaults.colorScheme`(スキームの実体は同ファイルの `schemes`)/ Mac: `iterm2/herdr.json` の色定義
- **herdr の UI テーマ** — `herdr/config.toml` の `[theme]`(OS 共通)

**端末は暗い配色、その上に乗る herdr の UI は明るい配色 — これは意図した組み合わせ。** 端末側は「背景色と ANSI 0–15 が実際に何色になるか」だけを決め、herdr は自分の UI(サイドバー・ペイン境界・ステータス)を自前のテーマ設定で描く。端末を暗くしても herdr は追随しない。herdr の UI を明るくしているのはワークスペースの選択状態を判別しやすくするためで、端末の明暗に自動追随させず、明るい側を明示指定している。

フォントは両 OS で同じものに揃える。名前とサイズを持つのは Win: `windows-terminal/settings.json` の `profiles.defaults.font` の `face` / `size` / Mac: `iterm2/herdr.json` の `Normal Font`(名前とサイズを 1 つの文字列で持つ)。Mac と Windows でフォント名の表記が違うので、値は両ファイルをそれぞれ見ること。

Windows Terminal ではテーマ・フォントを `profiles.defaults` に置き、**全プロファイルが継承する**。個別プロファイルでの上書きは行わない — プロファイルを増やしても設定を足す必要が無いのが狙い。

## 配置方式

**dotfiles が正。** `./setup.sh` は管理対象のファイルを丸ごと上書きする(部分マージはしない)。配置先が既に dotfiles と同一なら何もしない。

管理対象と配置先:

| ファイル | 配置先 |
|---|---|
| `herdr/config.toml` | `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml` |
| `iterm2/herdr.json`(Mac) | `~/Library/Application Support/iTerm2/DynamicProfiles/herdr.json` |
| `windows-terminal/settings.json`(WSL) | Windows 側 `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` |

herdr の設定の配置先は `XDG_CONFIG_HOME` に従う(`~/.config` 決め打ちではない) — herdr 自身がそちらしか読まないため。絶対パスでない値は XDG 仕様どおり無視して既定値に戻し、そのことを警告する。

**上書きの代償: 配置先にしか無い設定は消える。** herdr の UI から変えた設定や、Windows Terminal が自分で書いた設定も、次の `./setup.sh` で dotfiles の内容に戻る。残したいものは dotfiles 側に入れる — これが唯一の運用。

**退避(バックアップ)。** 上書きの直前に、配置先の既存ファイルを `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-backups` へ退避し、退避先のパスを表示する。既存ファイルが無いとき、および既に dotfiles と同一で上書きが起きないときは退避しない。Mac も WSL も同じ扱い。**退避ファイルは剪定しないので増え続ける。不要になったら自分で消すこと。**

**配置先が symlink だったとき(手作業が要る)。** 配置先がリンクで、その中身が dotfiles と違う場合、リンクは通常ファイルに置き換わる。リンクが指していた先は書き換えずそのまま残す — 管理対象の外にあるファイルを書き換えないため。このとき退避に入るのは**リンク先の内容であってリンクそのものではない**ので、退避を戻しても内容が戻るだけでリンクは戻らない(指す先が存在しないリンクなら、退避すべき内容が無いので退避も取られない)。中身が dotfiles と一致しているリンクはそのまま残る。これは失敗ではなく警告で、**リンクが必要だったなら自分で張り直すこと。**

**失敗したとき。** 配置に失敗したファイルがあっても、その場で警告して残りの配置は続行し、最後に失敗したファイルを列挙して非 0 で終了する。配る先が無い場合(非 WSL の Linux、Windows Terminal が入っていない Windows)は失敗ではなくスキップとして報告し、終了コードは 0。

## セットアップ

### WSL (Windows)

```sh
./setup.sh
```

herdr の設定と、Windows 側の Windows Terminal の `settings.json` を配置する(配置先・上書き・退避は「配置方式」を見ること)。

**フォントは手動**(WSL から Windows にはインストールできない)。入れるフォントの名前は `windows-terminal/settings.json` の `profiles.defaults.font` の `face` にある。その名前は配布物の版まで含んだ完全な名前なので、名前で配布元を探し、その名前どおりのフォントを Windows 側にインストールすること。README はフォント名を持たない(冒頭の規則のとおり)。

### Mac

```sh
./setup.sh
```

herdr の設定と、iTerm2 の Dynamic Profile を配置する。Dynamic Profile は iTerm2 が未導入でも配置する(iTerm2 は起動時にそのディレクトリを読む)。

フォントは Homebrew があれば `./setup.sh` が cask で入れる(cask 名は `setup.sh` の中にある。読者が自分でコマンドを打つ必要は無い)。Homebrew が無い、または install に失敗した場合は警告するだけで失敗には数えない(フォントは管理対象ファイルではない) — そのときは WSL 節と同じく手動で入れる。Mac 側の名前は `iterm2/herdr.json` の `Normal Font` にある。再実行すべき brew のコマンドは `./setup.sh` の警告がそのまま表示する。

#### 初回のみ: herdr プロファイルをデフォルトにする(必須・手動)

キーマッピングは Dynamic Profile「herdr」に入っているため、**そのプロファイルで開いたウィンドウにしか効かない**。
デフォルトにしていないと、通常のウィンドウでは `⌃⌘[` などが素通りして herdr のワークスペース切り替えが動かない。

1. iTerm2 の Settings(`⌘,`)→ Profiles → 左の一覧から **herdr** を選択
2. 下部の **Other Actions...** → **Set as Default**
3. **新しいウィンドウを開く**(`⌘N`)。既存のウィンドウは開いた時のプロファイルを保持するため、設定しても切り替わらない

`./setup.sh` は herdr がデフォルトプロファイルでない場合に警告を出す(iTerm2 が一度も起動されていないマシンでは、どれがデフォルトか分からない旨を出す)。どちらも警告であって失敗ではない。
