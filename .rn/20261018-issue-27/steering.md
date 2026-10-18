Rn version: 0.8.0

# Goal

Mac で英語/日本語入力の切り替えを、左 ⌘ 単押し = 英数、右 ⌘ 単押し = かな にする(Issue #27)。
いまは左下端の fn(地球儀)キーのトグルだけで、遠いうえに今どちらのモードかを確かめてから打つ必要がある。
Ctrl+Space(VS Code の Emacs キーバインドのマーク設定)と ⌘Space(Spotlight)は既に使われているので触らない。

clone して `./setup.sh` を流すだけで次の Mac でもこの状態になる — herdr やターミナルの設定と同じ保証にする。

# Acceptance criteria

- Mac で `./setup.sh` を流すと、`dominion525/tap/cmd-eikana`(Apple Silicon 版のフォーク)が Homebrew から
  入る。元の cask `cmd-eikana` は使わない
- 権限(入力監視・アクセシビリティ)が付いたあとは、左 ⌘ 単押しで英数、右 ⌘ 単押しでかなに切り替わり、
  ⌘ と他のキーの組み合わせ(⌘C など)はこれまで通り効く
- 権限はスクリプトで付けられないので、付いていない間は `./setup.sh` がその旨と「システム設定 >
  プライバシーとセキュリティ」の入力監視・アクセシビリティの2つを名指しで伝え、run を完了扱いにしない
  (FAILURES に載り非ゼロで終わる)。手で付けたあとの再実行では完了になる
- 再ログイン後もアプリが自動で起動して、同じ切り替えが効く
- Ctrl+Space と ⌘Space の持ち主(VS Code・Spotlight)は変わらない
- Windows(WSL)側の挙動は何も変わらない

# Assumptions

- tap の cask は v2.6.0、arm64 専用・macOS 13 以上。いまの Homebrew は未 tap のサードパーティ cask を
  `brew install` 一発では入れず、先に `brew tap dominion525/tap` が要る(このマシンで確認、2026-10-18)
- アプリは初回起動時にログイン項目へ自分を登録する(`toggleLaunchAtStartup.swift` の
  `prepareLaunchAtStartupOnLaunch`、ソースで確認)。既定の割り当てが左 ⌘ = 英数・右 ⌘ = かな であることは
  **未検証**(実機で確かめる)
- 権限の状態は macOS の権限DB(TCC.db)からは読めない(このターミナルでは authorization denied)。代わりに
  「アプリのプロセスがキーボードのイベントタップを持っているか」で判定する。アプリは両方の権限が揃うまで
  タップを作らない(`KeyEvent.swift`)。タップの一覧は `CGGetEventTapList` を JXA(osascript)から呼んで
  取れ、各タップの持ち主 PID が読める(このマシンで確認)
- このマシンには既に azooKey(日本語入力)・AltTab が入っている。かなキーで azooKey に切り替わることを
  実機で確かめる

# Rules

- commit and push every change; one completion marker per task
- 会話・ドキュメントは日本語(コード・コミットメッセージ・コメントは英語。repo の慣習に合わせる)
- 過去セッションの `.rn/` 配下は読むだけで書き換えない
- README には意図だけを書き、設定値やアプリ名の細部は書かない
- レビューは目的に錨を下ろす。1人用 dotfiles。完了基準に照らして効かない指摘は挙げさせない

# Tasks

### #1: setup.sh で ⌘英かな を入れ、権限が付くまで完了扱いにしない

**Purpose**: Mac で `./setup.sh` を流すと ⌘英かな が入って起動し、権限が付いていれば左右 ⌘ で
英数/かなが切り替わり、付いていなければ何を手でやればよいかを伝えて失敗として終わる。

**Prerequisites**: none

**Steps**:

- [x] `lib/` に ⌘英かな の導入(tap → cask install → 起動)と権限の判定を足し、Mac の分岐から呼ぶ
- [x] このマシンで `./setup.sh` を流し、権限が無い状態で FAILURES に載り、2つの設定名が表示されることを確認する
- [x] ユーザーに権限を付けてもらい、再実行で完了になること、左右 ⌘ で切り替わり ⌘C 等が効くことを確認する
- [x] 2回目以降の実行(導入済み・起動済み)で再インストールせず完了になることを確認する
- [x] README に、権限だけは手で付ける必要があることを意図として足す
- [x] self-check (OK/NG per completion criterion, record in checks/1.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium; QA・Verification と1回にまとめて実施)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- `./setup.sh` 後、入っている cask `cmd-eikana` のインストール記録の入手元が `dominion525/tap` である
  (元の cask と名前が同じで `brew list` では区別できない)。元の cask が入っていれば失敗として入れ替えを案内する
- 権限が無い状態の `./setup.sh` が、入力監視とアクセシビリティを名指しした案内を出し、FAILURES に載せて非ゼロで終わる
- 権限を付けたあとの `./setup.sh` が `Done.` で終わり、左 ⌘ 単押しで英数・右 ⌘ 単押しでかなに切り替わり、⌘C 等の組み合わせが効く
- アプリがログイン項目に登録されている
- Linux(WSL)の分岐からは新しい処理が呼ばれない
- Ctrl+Space・⌘Space の割り当てが変更前と同じ

### #2: Evaluation sign-off

**Purpose**: Acceptance criteria の確認結果をユーザーに承認してもらう。

**Prerequisites**: #1

**Steps**:

- [x] Acceptance criteria の確認結果をユーザーに提示する
- [x] `/rn:ty`(承認)または `/rn:gm`(修正 → 対応して再提示)で判断を受ける

**Completion criteria**:

- Acceptance criteria の確認結果がユーザーに承認されている

# State

(written by /rn:dn, read and reset to this placeholder by /rn:up. `Status` is `paused` while a
session is suspended — the signal /rn:up and /rn:dn search for — and resets to `not suspended` here,
so only a genuinely suspended session reads `paused`.)

- **Status**: not suspended
- **Date**: YYYY-MM-DD
- **Last completed**: #N description
- **Next**: #N description
- **Notes**: bounded forward pointer — branch/PR, next concrete action, open blockers, user-deferred paths, open questions / pending decisions not yet captured in `design.md`; not a re-narration of the session (that lives in `git log`)
