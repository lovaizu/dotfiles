# herdr4mac — design notes

Not read at runtime — for whoever maintains the design and needs to judge whether a decision is still
right when requirements change.

## 1. Background & Goals

### 1.1 What is the goal?

dotfiles の目的(Win / Mac の端末環境を clone → setup 一発で再現し、毎回設定しない)に沿って、
Mac(iTerm2)対応を追加し、Win(Windows Terminal)側も含めて設定を統一仕様
(テーマ・フォント・herdr 操作・即時切替キー・⇧Enter)に揃える。
あわせて、同じ「clone → setup 一発」の対象に Claude Code のユーザー設定
(`~/.claude/settings.json` とステータスライン用シェル)を加える。

### 1.2 What goes wrong without this?

Mac では herdr の workspace / agent 切替に毎回プレフィックス2ストロークが必要で Win と操作感が
揃わず、テーマ・フォントも手動設定になる。また統一仕様が明文化されていないと、OS ごとの設定が
それぞれ独自に育って再び乖離する。

### 1.3 What does reaching it require?

統一仕様の明文化(README の対応表)、iTerm2 側のキー→バイト列マッピングと色・フォントの
プロファイル定義、WT 側の別名チョード整理、それらを OS 判定つきでインストールする setup.sh。
加えて Claude Code のユーザー設定をホーム非依存の形で持ち、setup.sh の共通部から配置すること。

### 1.4 What is out of scope?

herdr 本体・iTerm2 のインストール、Win 側フォントのインストール(WSL からは不可能 — README の
手動手順に委ねる)、シェルの統一(Win は PowerShell / WSL bash、Mac は zsh のまま — herdr の中の
体験が揃えば足りる)、iTerm2 のプロファイル外グローバル設定の管理、Claude Code の
`~/.claude` 配下のうち settings.json / statusline.sh / themes 以外(プラグイン実体・履歴・
認証情報・herdr 統合フックの本体・output-styles)。

## 2. Assumptions & Constraints

### 2.1 What do we take as true?

herdr の config.toml は OS 共通(XDG パスも共通、未検証)。HHKB では Windows の Alt 位置のキーが
Mac では Cmd — よって Win の ctrl+alt 系は Mac では ⌃⌘ 系が同じ指運びになる。iTerm2 は `⌃T` を
既定で奪わない(⌘T が新タブ)ため、WT で必要だった「ctrl+t 無効化」に相当する設定は不要。
WT の ctrl+shift / alt+shift 別名チョードは使われておらず削除してよい(ユーザー確認済み)。

### 2.2 What binds the solution?

iTerm2 は WT のような単一の可搬な settings.json を持たず、設定は `com.googlecode.iterm2.plist` に
集約される — dotfiles で扱うにはファイル1個で完結し、起動中でも安全に読み込める仕組みが要る。
setup は Win 側も WSL の bash で実行される前提(既存 setup.sh の方式)なので、両OSとも bash 1本の
エントリで書ける。既存の `backup_then_copy` によるコピー方式(シンボリックリンクなし)を踏襲する。

## 3. Design overview

### 3.1 What is the core idea, and why does it solve the problem?

「共通層+OS別層」の2層構成にする。共通層 = herdr config と統一仕様(README の対応表)。
OS別層 = その仕様を各ターミナルの語彙に翻訳した設定ファイル(WT の settings.json / iTerm2 の
Dynamic Profile)。仕様を README に1か所で明文化することで、両OSの設定が同じ使い勝手に収束し、
将来の変更も「仕様を直す → 両OSの翻訳を直す」という手順に固定される。iTerm2 側は
**Dynamic Profiles**(`~/Library/Application Support/iTerm2/DynamicProfiles/` に置いた JSON を
自動読み込み)を使う — キー・色・フォントがプロファイル単位で JSON 1ファイルに収まり、既存の
コピー方式にそのまま乗る。

### 3.2 What are the pieces, and what is each responsible for?

- `README.md` — 統一仕様の源: 操作×OS別キー対応表、テーマ・フォント、セットアップ手順。
- `herdr/config.toml` — OS 共通の herdr 設定(本セッションでは不変)。
- `windows-terminal/settings.json` — 統一仕様の Win 翻訳(ctrl+alt 系のみに整理)。
- `iterm2/herdr.json` — 統一仕様の Mac 翻訳(⌃⌘ 系 + ⇧Enter + Gruvbox Dark + HackGen)。
- `claude/settings.json` — Claude Code のユーザー設定。ホーム依存パスは `"$HOME/…"` で記述。
- `claude/scripts/statusline.sh` — ステータスライン生成スクリプト(ホーム非依存、そのまま配置)。
- `claude/themes/catppuccin-{mocha,latte}.json` — `theme` が参照するカスタムテーマの実体。
- `setup.sh` — 単一エントリ: 共通部(herdr + Claude Code)→ `uname` で分岐 → darwin(iTerm2 配置+
  brew があればフォント)/ WSL(WT 配置)。

### 3.3 How does work move?

両OSとも `./setup.sh` を実行 → 共通部が herdr config と Claude Code 設定を配置 → OS 判定 → darwin なら Dynamic
Profile 配置(iTerm2 が監視していて再起動不要で反映)+フォント、WSL なら WT の settings.json を
配置。使い勝手を変えたいときは README の仕様を先に直し、両翻訳ファイルを追随させる。

## 4. Detailed design

### 4.1 What does the README spec guarantee, and how is a breach caught?

保証: 両OSのキー割り当て・送信バイト列・外観の単一の正が存在し、設定ファイル間の乖離を判定できる。
破れの検出: 各タスクの completion criteria が「README の対応表と一致」を要求しており、照合は
タスク検証(checks/)で記録される。将来の変更では README と両翻訳の diff が同一 PR に並ぶことで
乖離が見える。

### 4.2 What does the iTerm2 Keyboard Map guarantee, and how is a breach caught?

保証: `⌃⌘[`/`⌃⌘]`/`⌃⌘U` が herdr のプレフィックス列(0x14 + 文字)、`⇧Enter` が `\n` を送信する。
エントリは iTerm2 の `0x<keycode>-0x<modifier flags>` 形式、アクションは Send Escape Sequence /
Send Text。破れの検出: 作成時のキーコード手計算照合(タスク#2)と、ユーザーの実機確認(タスク#5)。
macOS / iTerm2 既定とは ⌃⌘ 系・⇧Enter とも衝突なし(⌃⌘F フルスクリーンとは別キー)。

### 4.3 What does the Dynamic Profile guarantee, and how is a breach caught?

保証: JSON が valid で Guid / Name を持てば iTerm2 が自動登録し、Guid 固定なので再コピー時も同一
プロファイルの更新になる(重複しない)。破れの検出: JSON 構文エラー時はプロファイルが現れない —
タスク#2 の `json.tool` 検証とタスク#4 の配置確認で事前に捕捉する。

### 4.4 What does the WT cleanup guarantee, and how is a breach caught?

保証: 即時切替は `ctrl+alt` 系3キーのみになり、README の対応表と1:1 になる。⇧Enter・`ctrl+t`
無効化・WT 固有キー・外観・プロファイルは従来のまま。破れの検出: タスク#3 で削除対象以外に diff が
ないことと未使用 action が残らないことを照合。実機は次回 Win 同期時のユーザー確認(タスク#5 で依頼)。

### 4.5 What does the setup.sh OS dispatch guarantee, and how is a breach caught?

保証: darwin では WT ブロック(`wslpath`/`cmd.exe` 依存)に到達せず、brew 不在でもエラー終了しない。
WSL では従来と同じファイルを同じ場所に配置する。破れの検出: mac での実行テスト(exit 0 + 配置確認、
brew 分岐のメッセージ)と、WSL 経路のコードレビュー(タスク#4)。

### 4.6 What does the Claude Code settings deployment guarantee, and how is a breach caught?

保証: 両OSで同じ Claude Code のユーザー設定(出力スタイル・努力度・テーマ・プラグイン・
ステータスライン・herdr の SessionStart フック)が再現され、ホームディレクトリのパスが
OS ごとに異なっても正しい実パスを指す。

仕組み: settings.json の `command` はシェル経由で実行される — Claude Code 2.1.241 のバイナリで検証済み
(hook `command` スキーマの説明が "When absent [args], `command` runs through a shell (bash on POSIX,
PowerShell on Windows without Git Bash)" と述べ、statusLine も同じランナー `Oes(…,"StatusLine",…)` を
通る)。よって dotfiles 側は `"$HOME/…"` を直接書き、setup.sh は変換なしの `backup_then_copy` で
配置する。ホームパスに空白が含まれても壊れないよう、両 command のパスはダブルクォートで囲む。

当初はプレースホルダ(`__HOME__`)+ setup 時の置換を採る設計だったが、`$HOME` 展開が検証できたため
不採用にした。置換方式は sed の置換文字列側で `&` がマッチ全体に解釈されるなど無言で壊れる失敗モードを
持ち込むため(実測: ホームが `/home/a&b` だと `/home/a__HOME__b` になる)、機構を持たない方が堅い。

境界: `~/.claude/hooks/herdr-agent-state.sh` は herdr の統合インストーラが管理するファイル
(冒頭に "managed by herdr" と明記され、再インストールで上書きされる)なので dotfiles では持たない。
settings.json 側の SessionStart エントリだけを持ち、本体不在なら setup.sh が警告する。
`~/.claude/output-styles/sleek.md` も持たない — 現行 settings.json が参照していない
(`outputStyle` は組み込みの `Concise`)ため。

一方、`theme: "custom:catppuccin-mocha"` の実体 `~/.claude/themes/catppuccin-mocha.json` は
**持つ**。無いと Claude Code は警告なく組み込み dark にフォールバックし、設定値だけが残って
配色が別物になるため — 「設定名は運べても実体が運べていない」型の破れで、静的検証では捕まらない。

前提: statusline.sh は `jq` に依存する。不在時は exit 0 のまま ` |  | dir@branch` を返して無言で
劣化するため、setup.sh が `jq` の存在を確認して警告する(mac は OS 同梱だが Ubuntu/WSL は既定で不在)。

破れの検出: 配置後の settings.json が dotfiles 側とバイト一致することと JSON 妥当性(タスク#7)、
原本との diff 照合(タスク#6)、`/config` 上での `remoteControlAtStartup` の目視確認(タスク#7)。

## 5. Alternatives considered

### 5.1 Why this shape, and not another?

- **setup を OS 別ファイルに分割(setup-mac.sh / setup-win.sh)**: エントリが2つになり
  「どれを実行するか」を README で説明する手間が増える。共通部(herdr)が重複するか相互 source に
  なり、リポジトリの規模に対して構造が重い。`uname` 分岐つきの単一 `setup.sh` なら両OSとも
  同じコマンドで済む(Win 側も WSL bash で実行する既存前提に乗る)。
- **「Load preferences from custom folder」+ plist 全体管理**: iTerm2 の全設定を奪い、plist は
  バイナリ化・頻繁な書き戻しで diff が汚れる。必要なのは1プロファイル分だけなので過剰。
- **`defaults write` の羅列**: Keyboard Map の入れ子 dict が壊れやすく、iTerm2 起動中の書き込みは
  上書きされ得る。
- **Karabiner-Elements でキー変換**: 端末外のグローバル常駐が増え、iTerm2 以外にも効く。端末内で
  完結する Dynamic Profiles が最小。
- **WT の別名チョードを Mac にも展開**: 統一の方向と逆(使われていない別名を増やす)。むしろ Win 側を
  ctrl+alt 系のみに整理して両OSを1:1 にする。
- **`~/.claude` ごとシンボリックリンク**: プラグインキャッシュ・履歴・認証情報など Claude Code が
  実行時に書き込む大量のファイルを巻き込む。管理したいのは settings.json と statusline.sh の2つだけ。
- **settings.json をそのまま(リテラルの絶対パスのまま)持つ**: mac(`/Users/kiyo`)と WSL
  (`/home/kiyo`)でホームパスが異なるため片方で壊れる。
- **`__HOME__` プレースホルダ + setup 時の sed 置換**: `$HOME` 展開が検証できた今では余分な機構。
  sed は置換文字列側の `&` `\` やデリミタ文字で無言で壊れ、しかも結果は有効な JSON のままなので
  検出しづらい。採らない。
- **herdr のフックスクリプト本体も dotfiles で持つ**: herdr の統合が再インストール時に上書きする
  ため二重管理になり、バージョン不整合を招く。

### 5.2 What did we trade away?

Dynamic Profile はデフォルトプロファイル化を自動でできない(初回に iTerm2 UI で一度設定する手作業が
残る)。Win 側フォントは自動化されない(WSL から Windows へのフォントインストールは不可 — README の
手動手順で受容)。シェルは OS ごとに異なるまま(統一しない判断)。グローバルな iTerm2 設定
(ウィンドウ挙動等)は管理対象外のまま。Claude Code 側は、設定を手元で変えた(/config など)場合に
dotfiles へ戻す作業が手動で残る — 一方向(dotfiles → ホーム)の配置に割り切った。
