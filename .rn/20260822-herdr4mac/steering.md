Rn version: 0.8.0
Design: .rn/20260822-herdr4mac/design.md

# Goal

WSL の herdr + Windows Terminal で実現している環境を macOS の iTerm2 で再現する。Windows Terminal
側の設定は2系統ある: ① `ctrl+t` の既定動作を無効化して herdr のプレフィックス(`^T`)を通す、②
`ctrl+alt+{[,],u}` で herdr のプレフィックス列(`^T [` / `^T ]` / `^T u`)を一発送信し、プレフィックス
操作なしで workspace / agent を即時切替する。Mac では HHKB で Alt と Cmd が同じ物理位置にあるため、
② を `⌃⌘[` / `⌃⌘]` / `⌃⌘U` に割り当てる(① は iTerm2 が `⌃T` を既定で奪わないため設定不要)。
あわせて `⇧Enter` での改行送信、Gruvbox テーマ、HackGen Console NF フォントも再現する。
これらを dotfiles に追加し、setup.sh を mac 対応にしてインストールできるようにする。

# Acceptance criteria

- dotfiles に iTerm2 用設定が存在し、それをインストールした iTerm2 で:
  - `⌃⌘[` が `0x14 0x5b`(`^T [`)、`⌃⌘]` が `0x14 0x5d`(`^T ]`)、`⌃⌘U` が `0x14 0x75`(`^T u`)を端末に送信する
  - `⇧Enter` が `\n`(0x0a)を送信する
  - `⌃T` は横取りされず端末(herdr)に届く
  - カラースキームは Gruvbox Dark、フォントは HackGen Console NF 13pt
- mac 上で `setup.sh` を実行すると herdr config と iTerm2 設定がインストールされ、Windows Terminal
  部分はエラーにならずスキップされる(`wslpath` / `cmd.exe` 不在で落ちない)
- WSL 上での `setup.sh` の既存動作(herdr config と WT settings.json のインストール)が変わらない
- 既存ファイル(herdr/config.toml, windows-terminal/settings.json)は変更されない

# Assumptions

- herdr の `config.toml` は OS 共通で、mac でもそのまま `~/.config/herdr/config.toml` に置けば動く(未検証)
- iTerm2 はユーザーがインストール済み。HackGen Console NF のインストールは本セッションのスコープ外
  (未導入ならフォールバックフォントで表示される)
- iTerm2 の実機での鍵送信確認はユーザーが行う(エージェントは設定ファイルの静的検証まで)
- `ctrl+shift` / `alt+shift` 系の WT の別名チョードは Mac では再現しない(ユーザー確認済み: 本命は ctrl+alt 系)

# Rules

- commit and push every change; one completion marker per task
- 会話・ドキュメントは日本語(コード・コミットメッセージは英語)
- 既存の WSL / Windows 向けファイルには手を入れない

# Tasks

### #1: iTerm2 Dynamic Profile を作成する

**Purpose**: herdr 用キーマッピング・Gruvbox Dark・HackGen フォントを含む iTerm2 Dynamic Profile
JSON を `iterm2/herdr.json` として dotfiles に追加する。

**Prerequisites**: none

**Steps**:

- [ ] `iterm2/herdr.json` を作成: Guid 固定の Dynamic Profile。Keyboard Map に `⌃⌘[` → `0x14 [`、`⌃⌘]` → `0x14 ]`、`⌃⌘U` → `0x14 u`、`⇧Enter` → `\n` の Send-Text(escape sequence)エントリ、Gruvbox Dark の Ansi 0–15 / Foreground / Background / Cursor / Selection 色、`Normal Font: HackGenConsoleNF-Regular 13` を定義
- [ ] JSON の構文と必須キー(Guid / Name / Keyboard Map のキーコード表記)を静的検証(`python3 -m json.tool` + キーコードの手計算照合)
- [ ] self-check (OK/NG per completion criterion, record in checks/1.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- `iterm2/herdr.json` が有効な JSON で、iTerm2 の Dynamic Profile 仕様の必須キー(Guid, Name)を持つ
- Keyboard Map に4エントリが存在し、キーコード(修飾フラグ含む)とアクション(Send text with escape sequences 相当)・送信バイト列が Acceptance criteria の対応表(⌃⌘[→`^T [`, ⌃⌘]→`^T ]`, ⌃⌘U→`^T u`, ⇧Enter→`\n`)と一致する
- 色定義が windows-terminal/settings.json の Gruvbox Dark スキームの16色+前景/背景と同一の値である
- 既存ファイルに差分がない

### #2: setup.sh を mac 対応にする

**Purpose**: darwin 判定を追加し、mac では iTerm2 Dynamic Profile をインストールし
Windows Terminal 部分をスキップするようにする。

**Prerequisites**: #1

**Steps**:

- [ ] `setup.sh` に OS 判定を追加: darwin では `iterm2/herdr.json` を `~/Library/Application Support/iTerm2/DynamicProfiles/` に `backup_then_copy` でインストールし、WT ブロックはスキップ。それ以外(WSL)は従来どおり
- [ ] mac 上で `setup.sh` を実行し、エラーなく完了して Dynamic Profile が配置されることを確認(herdr config の配置も含む)
- [ ] `bash -n` と shellcheck(あれば)で構文検証。WSL パス(wslpath 不在時)の分岐をコードレビューで確認
- [ ] self-check (OK/NG per completion criterion, record in checks/2.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- mac 上で `setup.sh` が exit 0 で完了し、`~/Library/Application Support/iTerm2/DynamicProfiles/herdr.json` と `~/.config/herdr/config.toml` が配置されている
- スクリプトの WSL 経路は変更前と同一の動作をする(darwin 分岐追加以外の差分がない)
- `wslpath` / `cmd.exe` が存在しない環境で実行してもエラー終了しない

### #3: Evaluation sign-off

**Purpose**: Acceptance criteria の充足をユーザーに提示し、承認を得る。

**Prerequisites**: #1, #2

**Steps**:

- [ ] Acceptance criteria を1件ずつ検証した結果(設定ファイルの対応表・setup.sh 実行結果・ユーザーの実機確認手順)を提示する
- [ ] ユーザーの実機確認(iTerm2 再起動 → herdr 上で ⌃⌘[/⌃⌘]/⌃⌘U/⇧Enter/⌃T の動作)を依頼する
- [ ] verdict を /rn:ty(approve)または /rn:gm(revise → 対応して再提示)で受ける

**Completion criteria**:

- Acceptance criteria の全項目に OK/NG と根拠が提示され、ユーザーが /rn:ty で承認している

# State

(written by /rn:dn, read and reset to this placeholder by /rn:up. `Status` is `paused` while a
session is suspended — the signal /rn:up and /rn:dn search for — and resets to `not suspended` here,
so only a genuinely suspended session reads `paused`.)

- **Status**: not suspended
- **Date**: YYYY-MM-DD
- **Last completed**: #N description
- **Next**: #N description
- **Notes**: bounded forward pointer — branch/PR, next concrete action, open blockers, user-deferred paths, open questions / pending decisions not yet captured in `design.md`; not a re-narration of the session (that lives in `git log`)
