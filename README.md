# dotfiles

Windows (WSL + Windows Terminal) と Mac (iTerm2) の端末環境と、Claude Code への個人用の指示を、clone して `./setup.sh` を実行するだけで再現するためのリポジトリ。

## 設定対象

| 何を | どのファイルが持つか |
|---|---|
| herdr のキー割り当てと UI テーマ(OS 共通) | `herdr/config.toml` |
| Claude Code への個人用の指示(OS 共通) | `claude/CLAUDE.md` |
| Windows Terminal の外観とキー | `windows-terminal/settings.json` |
| iTerm2 の外観とキー | `iterm2/herdr.json` |

### Claude Code への指示をどこに書くか

指示は 3 層に分かれていて、`claude/CLAUDE.md` が持つのはそのうちの 1 層だけ。

- **`claude/CLAUDE.md` = 基本指針。** どの手順にも、どのリポジトリにも依存しない、Claude との関係そのもの。プラグインを全部外しても意味が通る。
- **プラグイン(rn など)= 手順。** 何をどの順でやり、何を残し、どこで止まるか。
- **スキル = ある領域の知識。** その領域で何が定石で、何を避けるか。

行を足すときは消去法で決める。手順の 1 ステップならプラグインへ、ある領域の知識ならスキルへ。どちらでもなければ `claude/CLAUDE.md` に残る。

## 直す前に

設定ファイルを素直に読むと直したくなるが、意図してそうしている点が3つある。

- **端末は暗い配色、その上で動く herdr の UI は明るい配色。** ちぐはぐに見えるが、ワークスペースの選択状態を判別しやすくするために明るい側を明示指定している。端末の明暗に追随させない。
- **Mac のキーが `⌘` 側にあるのは HHKB の物理位置に合わせているから。** Win の `Alt` と Mac の `⌘` が同じ位置にあるので、同じ指の形で同じ操作になる。「Mac らしい」キーに直すと両 OS の統一が崩れる。
- **dotfiles が正で、`./setup.sh` は管理対象を丸ごと上書きする。** 端末や herdr の UI から変えた設定も、置いた先のファイルを手で直した分も、次の実行で dotfiles の内容に戻る。残したいものは dotfiles 側に入れること。

## セットアップ

両 OS とも:

```sh
./setup.sh
```

何をどこへ置いたか、退避を取ったか、何に失敗したかは `./setup.sh` が実行時に表示する。以下は `./setup.sh` が実行できないので手でやる。

### フォント

入手先は両 OS 共通で [配布元のリリースページ](https://github.com/yuru7/HackGen/releases)。入れるフォントの名前は設定ファイルにある(Win: `windows-terminal/settings.json` の `profiles.defaults.font` の `face` / Mac: `iterm2/herdr.json` の `Normal Font`)。

- **Windows: 必ず手動。** WSL から Windows へはインストールできない。
- **Mac: Homebrew があれば `./setup.sh` が入れる。** 無い、または失敗したときだけ手動(再実行するコマンドは警告がそのまま表示する)。

### Mac 初回のみ: herdr プロファイルをデフォルトにする

キー割り当ては Dynamic Profile「herdr」にあるので、**そのプロファイルで開いたウィンドウにしか効かない**。デフォルトにしていないと、通常のウィンドウではキーが素通りする。

1. iTerm2 の Settings(`⌘,`)→ Profiles → 左の一覧から **herdr** を選択
2. 下部の **Other Actions...** → **Set as Default**
3. **新しいウィンドウを開く**(`⌘N`)。既存のウィンドウは開いた時のプロファイルを保持する

`./setup.sh` はデフォルトになっていなければ警告する(失敗ではない)。
