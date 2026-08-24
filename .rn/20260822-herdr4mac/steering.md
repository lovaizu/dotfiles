Rn version: 0.8.0
Design: .rn/20260822-herdr4mac/design.md

# Goal

この dotfiles の目的は、Win(WSL + Windows Terminal)と Mac(iTerm2)の端末環境を
「clone → setup 一発」で再現し、毎回手で設定しなくて済むようにすること。そのために両OSの設定を
同じ使い勝手に統一して管理する — テーマ(Gruvbox Dark)、フォント(HackGen Console NF 13)、
herdr 操作(prefix `^T`)、プレフィックスなしの即時切替(Win: `ctrl+alt+{[,],u}` / Mac:
`⌃⌘{[,],U}` — HHKB では Alt と Cmd が同じ物理位置)、`⇧Enter` での改行送信。

本セッションでは Mac(iTerm2)対応を新規追加し、あわせて Win 側の設定内容を見直して統一仕様に
揃え、setup.sh を共通部+OS別の構成に再編する。統一仕様は README に明文化する。

さらに同じ考え方を Claude Code のユーザー設定にも広げる: `~/.claude/settings.json` と
ステータスライン用シェルスクリプトを dotfiles に取り込み、両OSで setup.sh から再現できるようにする。

# Acceptance criteria

- README に統一仕様が明文化されている: 操作×OS別キーの対応表(即時切替3操作・⇧Enter・プレフィックス
  パススルー)、テーマ・フォント、セットアップ手順(Win / Mac 双方)
- iTerm2 用設定が dotfiles に存在し、インストールした iTerm2 で:
  - `⌃⌘[` が `0x14 0x5b`(`^T [`)、`⌃⌘]` が `0x14 0x5d`(`^T ]`)、`⌃⌘U` が `0x14 0x75`(`^T u`)を送信する
  - `⇧Enter` が `\n`(0x0a)を送信する
  - `⌃T` は横取りされず端末(herdr)に届く
  - カラースキームは Gruvbox Dark、フォントは HackGen Console NF 13pt
- windows-terminal/settings.json が統一仕様に整理されている: 即時切替は `ctrl+alt` 系のみ
  (`ctrl+shift` / `alt+shift` の別名チョードは削除)、`⇧Enter`→`\n`・`ctrl+t` 無効化・外観・
  プロファイル定義は維持
- `setup.sh` が共通部(herdr config)+OS別(darwin: iTerm2 Dynamic Profile 配置と、Homebrew が
  あれば HackGen フォントのインストール / WSL: WT settings.json 配置)の構成で、両OSで exit 0 で
  完了する(darwin では `wslpath`/`cmd.exe` 不在で落ちない、WSL では従来と同等の配置結果)
- herdr/config.toml は OS 共通のまま(OS 別の分岐を持ち込まない)。`[keys]` は変更しない。
  `[theme]` は端末側テーマ(Gruvbox Dark)と揃える — herdr の UI テーマが `gruvbox`(dark)であること
- `claude/settings.json` が dotfiles にあり、ホーム依存の絶対パス(statusLine / hooks の command)が
  プレースホルダ化されていて、mac(`/Users/...`)と WSL(`/home/...`)の双方で正しい実パスに展開される
- `claude/settings.json` に `remoteControlAtStartup: false` が含まれる(キー名は Claude Code の
  設定スキーマで確認済み)。既存の設定値(outputStyle / effortLevel / theme / tui / enabledPlugins /
  extraKnownMarketplaces / statusLine / SessionStart フック / skipDangerousModePermissionPrompt /
  agentPushNotifEnabled)は現行の `~/.claude/settings.json` と同じ内容が保たれる
- `claude/scripts/statusline.sh` が dotfiles にあり、配置後のステータスラインが従来と同じ
  `C:…k/…k 5h:…% 7d:…% | モデル/努力度 | ディレクトリ@ブランチ` 形式で表示される
- `setup.sh` の共通部が両OSで `~/.claude/settings.json` と `~/.claude/scripts/statusline.sh` を配置し、
  既存ファイルは BACKUP_DIR に退避される。配置後の settings.json が有効な JSON である
- README に Claude Code 設定の管理対象・herdr 統合の前提(`hooks/herdr-agent-state.sh` は herdr 側が
  導入するため dotfiles では管理しない)・セットアップ手順が記載されている

# Assumptions

- herdr の `config.toml` は OS 共通で、mac でもそのまま `~/.config/herdr/config.toml` に置けば動く(未検証)
- iTerm2 はユーザーがインストール済み。mac のフォントは Homebrew(cask `font-hackgen-nerd`)が
  あれば setup.sh で入れ、なければスキップ(手動導入でも可)。Win 側のフォントインストールは
  WSL からは行えないため従来どおり手動(README に手順を記載)
- iTerm2 / WT の実機での鍵送信確認はユーザーが行う(エージェントは設定ファイルの静的検証まで)
- WT の `ctrl+shift` / `alt+shift` 別名チョードは削除してよい(本命は `ctrl+alt` 系 — ユーザー確認済み。
  削除自体の最終確認はプランゲートで取る)
- シェル自体は統一しない: Win は WT のプロファイル(PowerShell / WSL bash)、Mac は zsh のまま。
  herdr の起動は両OSとも手動
- `~/.claude/hooks/herdr-agent-state.sh` は herdr の統合インストーラが生成・上書きするファイル
  (ファイル冒頭に "managed by herdr" と明記)なので dotfiles では管理しない。settings.json の
  SessionStart エントリだけを持ち、スクリプト本体は herdr の導入に委ねる
- settings.json の `command` 文字列内で `$HOME` / `~` が展開されるかは未確認。展開有無に依存しない
  よう、dotfiles 側はプレースホルダを持ち、setup.sh が実パスへ置換して配置する
- `~/.claude/settings.json` は Claude Code 自身が(/config 等で)書き換えることがある。配置は
  「バックアップ+上書き」とし、手元で変えた設定を dotfiles に戻すのはユーザーの運用とする

# Rules

- commit and push every change; one completion marker per task
- 会話・ドキュメントは日本語(コード・コミットメッセージは英語)
- herdr/config.toml の `[keys]` には手を入れない(`[theme]` は端末側と揃えるため変更可)

# Tasks

### #1: README に統一仕様を定義する

**Purpose**: 両OSで揃える使い勝手(キー対応表・テーマ・フォント)とセットアップ手順を README に
明文化し、以降のタスクの仕様源にする。

**Prerequisites**: none

**Steps**:

- [x] README.md に記載: リポジトリの目的、操作×キー対応表(操作 / herdr 列 / Win キー / Mac キー)、テーマ・フォント、セットアップ手順(WSL: `./setup.sh`、mac: `./setup.sh`、Win フォントは手動)
- [x] self-check (OK/NG per completion criterion, record in checks/1.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- README に対応表があり、即時切替3操作(previous/next workspace, next agent)・⇧Enter・⌃T
  パススルーについて Win / Mac 双方のキーと送信内容(herdr 列)が読み取れる
- テーマ(Gruvbox Dark)・フォント(HackGen Console NF 13)と、両OSのセットアップ手順
  (フォントの入手方法含む)が記載されている
- 記載内容が steering の Acceptance criteria の対応表と矛盾しない

### #2: iTerm2 Dynamic Profile を作成する

**Purpose**: 統一仕様どおりのキーマッピング・Gruvbox Dark・HackGen フォントを含む iTerm2
Dynamic Profile JSON を `iterm2/herdr.json` として追加する。

**Prerequisites**: #1

**Steps**:

- [x] `iterm2/herdr.json` を作成: Guid 固定の Dynamic Profile。Keyboard Map に `⌃⌘[` → `0x14 [`、`⌃⌘]` → `0x14 ]`、`⌃⌘U` → `0x14 u`、`⇧Enter` → `\n` の Send-Text エントリ、Gruvbox Dark の Ansi 0–15 / Foreground / Background / Cursor / Selection 色、`Normal Font: HackGenConsoleNF-Regular 13` を定義
- [x] JSON の構文と必須キー(Guid / Name / Keyboard Map のキーコード・修飾フラグ表記)を静的検証(`python3 -m json.tool` + キーコードの手計算照合)
- [x] self-check (OK/NG per completion criterion, record in checks/2.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- `iterm2/herdr.json` が有効な JSON で、iTerm2 の Dynamic Profile 仕様の必須キー(Guid, Name)を持つ
- Keyboard Map に4エントリが存在し、キーコード(修飾フラグ含む)と送信バイト列が README の対応表
  (⌃⌘[→`^T [`, ⌃⌘]→`^T ]`, ⌃⌘U→`^T u`, ⇧Enter→`\n`)と一致する
- 色定義が windows-terminal/settings.json の Gruvbox Dark スキームの16色+前景/背景と同一の値である

### #3: Windows Terminal 設定を統一仕様に整理する

**Purpose**: windows-terminal/settings.json から別名チョード(`ctrl+shift` / `alt+shift` 系)を
削除し、即時切替を `ctrl+alt` 系のみに統一する。

**Prerequisites**: #1

**Steps**:

- [x] settings.json の keybindings から `ctrl+shift+[/]/u`・`alt+shift+[/]/u` のエントリを削除(sendInput アクション定義・`ctrl+alt` 系・⇧Enter・`ctrl+t` 無効化・その他 WT 固有キーと外観・プロファイルは維持)
- [x] JSON 構文検証と、残存キーバインドが README の対応表と一致することの照合
- [x] self-check (OK/NG per completion criterion, record in checks/3.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- settings.json が有効な JSON で、即時切替の keybinding が `ctrl+alt+[/]/u` の3つのみになっている
- `⇧Enter`→`\n`、`ctrl+t` 無効化、`ctrl+c/v`・`ctrl+shift+f`・`alt+shift+d`、外観(Gruvbox Dark /
  HackGen 13)、プロファイル定義に変更がない
- 未使用になった action 定義が残っていない

### #4: setup.sh を共通部+OS別構成に再編する

**Purpose**: OS 判定を導入し、共通部(herdr)のあと darwin では iTerm2 設定配置+フォント
(Homebrew があれば)、WSL では従来の WT 配置を行うようにする。

**Prerequisites**: #2, #3

**Steps**:

- [x] `setup.sh` を再編: 共通部(herdr config 配置)→ `uname` による OS 判定 → darwin: `iterm2/herdr.json` を `~/Library/Application Support/iTerm2/DynamicProfiles/` に `backup_then_copy`、`brew` があれば `font-hackgen-nerd` をインストール(なければメッセージを出してスキップ)/ それ以外(WSL): 従来の WT ブロック
- [x] mac 上で `setup.sh` を実行し、exit 0 で herdr config と Dynamic Profile が配置されること(brew 有無の両分岐のメッセージ)を確認
- [x] `bash -n`(+ shellcheck があれば)で構文検証。WSL 経路が従来と同等の配置を行うことをコードレビューで確認
- [x] self-check (OK/NG per completion criterion, record in checks/4.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- mac 上で `setup.sh` が exit 0 で完了し、`~/Library/Application Support/iTerm2/DynamicProfiles/herdr.json` と `~/.config/herdr/config.toml` が配置されている
- darwin では `wslpath` / `cmd.exe` 不在でもエラー終了せず、WT ブロックに到達しない
- WSL 経路は従来と同じファイルを同じ場所に配置する(herdr config + WT settings.json)
- Homebrew 不在の mac でもエラー終了しない

### #5: Evaluation sign-off

**Purpose**: Acceptance criteria の充足をユーザーに提示し、承認を得る。

**Prerequisites**: #1, #2, #3, #4, #6, #7, #8

**Steps**:

- [x] Acceptance criteria を1件ずつ検証した結果(README・両設定ファイルの対応表照合・setup.sh 実行結果)を提示する
- [x] ユーザーの実機確認を依頼する: mac は iTerm2 で ⌃⌘[/⌃⌘]/⌃⌘U/⇧Enter/⌃T(実施済み: raw モード捕捉で `14 5b 14 5d 14 75 0a 14` — 全キー期待どおり)、Win は次回同期時に WT で ctrl+alt 系
- [x] 評価中に判明した不具合に対応する(revise 1 巡目):
      (a) herdr プロファイルが iTerm2 のデフォルトでないとキーが効かない → setup.sh に検出警告、README に手順明記
      (b) `.bak` が DynamicProfiles 内に残り同一 Guid の二重プロファイルになる → バックアップ先を `~/.local/state/dotfiles-backups/` に変更
      (c) herdr の UI テーマが `gruvbox-light` で端末の Gruvbox Dark と不一致 → `gruvbox` に変更(steering の Rules / Acceptance criteria も更新)
- [x] ユーザーが新規ウィンドウ(⌘N)で確認: ワークスペース切り替えが効くこと、herdr UI が暗い配色になること(実施済み: 動作確認 OK)
- [ ] revise 2 巡目: Claude Code 設定(settings.json / statusline.sh)の dotfiles 化 — #6〜#8 として追加、完了後に再提示
- [ ] verdict を /rn:ty(approve)または /rn:gm(revise → 対応して再提示)で受ける

**Completion criteria**:

- Acceptance criteria の全項目に OK/NG と根拠が提示され、ユーザーが /rn:ty で承認している

### #6: Claude Code 設定ファイルを dotfiles に取り込む

**Purpose**: `~/.claude/settings.json` と `~/.claude/scripts/statusline.sh` を `claude/` 配下に
ホーム非依存の形で複製し、両OSから同じ設定を再現できる元データにする。

**Prerequisites**: none

**Steps**:

- [ ] `claude/settings.json` を作成: 現行 `~/.claude/settings.json` の内容を写し、`statusLine.command` と SessionStart フックの `command` 内のホームパスを `__HOME__` プレースホルダに置換。`remoteControlAtStartup: false` を追加
- [ ] `claude/scripts/statusline.sh` を作成: 現行 `~/.claude/scripts/statusline.sh` をそのまま複製(ホーム依存の記述がないことを確認)
- [ ] `python3 -m json.tool` で JSON 構文検証、`sh -n` で statusline.sh の構文検証、現行ファイルとの diff で意図した差分(プレースホルダ化+`remoteControlAtStartup`)のみであることを照合
- [ ] self-check (OK/NG per completion criterion, record in checks/6.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- `claude/settings.json` が有効な JSON で、`__HOME__` 以外にホーム依存の絶対パスを含まない
- 現行 `~/.claude/settings.json` との差分が「2箇所のパスのプレースホルダ化」と「`remoteControlAtStartup: false` の追加」のみで、他のキー・値が変わっていない
- `claude/scripts/statusline.sh` が `sh -n` を通り、現行の `~/.claude/scripts/statusline.sh` と
  バイト一致する
- 秘密情報(APIキー・トークン等)が含まれていない

### #7: setup.sh 共通部で Claude Code 設定を配置する

**Purpose**: setup.sh の共通部に Claude Code 設定の配置を追加し、両OSで `~/.claude/` 以下に
展開済みの settings.json と statusline.sh が置かれるようにする。

**Prerequisites**: #6

**Steps**:

- [ ] `setup.sh` の共通部に Claude Code ブロックを追加: `~/.claude/scripts/` を作成、`claude/scripts/statusline.sh` を `backup_then_copy` で配置して実行権を付与、`claude/settings.json` の `__HOME__` を `$HOME` に置換した一時ファイルを作って `~/.claude/settings.json` に `backup_then_copy`
- [ ] `~/.claude/hooks/herdr-agent-state.sh` が無い場合に警告を出す(herdr 統合が未導入だと SessionStart フックが空振りするため)
- [ ] mac 上で実行し exit 0、配置された settings.json が有効な JSON かつ `__HOME__` が残っていないこと、statusline.sh が実行可能なことを確認。`bash -n`(+ shellcheck があれば)で構文検証
- [ ] self-check (OK/NG per completion criterion, record in checks/7.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- mac 上で `setup.sh` が exit 0 で完了し、`~/.claude/settings.json` と
  `~/.claude/scripts/statusline.sh` が配置されている
- 配置された settings.json が有効な JSON で `__HOME__` を含まず、`command` のパスが実在ファイルを指す
- 既存の `~/.claude/settings.json` は上書き前に BACKUP_DIR に退避されている
- Claude Code ブロックが OS 判定より前(共通部)にあり、WSL 経路でも同じ配置が行われる。既存の
  herdr / iTerm2 / WT の配置動作は変わらない
- sed 置換がパス中の区切り文字で壊れない(`$HOME` に `/` が含まれても正しく置換される)

### #8: README に Claude Code 設定の管理範囲と手順を追記する

**Purpose**: dotfiles が管理する Claude Code 設定の範囲・herdr 統合との境界・セットアップ後の
確認方法を README に明文化する。

**Prerequisites**: #6, #7

**Steps**:

- [ ] README.md に節を追加: 管理対象(`claude/settings.json` / `claude/scripts/statusline.sh`)、配置先、`__HOME__` 置換の仕組み、`hooks/herdr-agent-state.sh` は herdr 側が導入する旨、`./setup.sh` 後に Claude Code を再起動して反映する旨
- [ ] 記載内容が steering の Acceptance criteria および実際の setup.sh の挙動と一致することを照合
- [ ] self-check (OK/NG per completion criterion, record in checks/8.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- README を読んだ第三者が、dotfiles が管理する Claude Code 設定ファイルと配置先、および
  管理しないもの(herdr 統合フックの本体)を区別できる
- 記載された手順が実際の setup.sh の挙動と一致し、README 内の既存記述(端末統一仕様)と矛盾しない


# State

(written by /rn:dn, read and reset to this placeholder by /rn:up. `Status` is `paused` while a
session is suspended — the signal /rn:up and /rn:dn search for — and resets to `not suspended` here,
so only a genuinely suspended session reads `paused`.)

- **Status**: not suspended
- **Date**: -
- **Last completed**: -
- **Next**: -
- **Notes**: -
