Rn version: 0.8.0

# Goal

Claude Code の質問文が、どちらのマシンの端末でも読める(Issue #13)。

Issue を書いた 2026-09-06 の時点では `theme` が `light`(明るい背景向け)で、暗い配色の端末では
質問文が読めなかった。その後 PR #11 で `claude/settings.json` の `theme` が `auto` になり、
設定の上では Issue の望む状態になっている。残るのは、実機の herdr の中で `auto` が暗いテーマを選び、
質問文が読めるかの確認だけ。

# Acceptance criteria

- Mac(iTerm2 + herdr)で、Claude Code の質問文と選択肢が読める
- Windows(Windows Terminal + WSL + herdr)で、Claude Code の質問文と選択肢が読める
- 読めない環境があれば、`./setup.sh` を流すだけでその環境でも読めるようになる

# Assumptions

- `auto` は端末に背景色を問い合わせて(OSC 11)テーマを決める。結果は `claude --debug` のログに
  `systemTheme: OSC 11 response=... detected=...` として出る(Claude Code 2.1.302 のバイナリで確認)
- 2台とも端末は暗い配色(iTerm2 のプロファイル、Windows Terminal の配色とも repo で確認)

# Rules

- commit and push every change; one completion marker per task
- 会話・`.rn/` は日本語。コード・コミットメッセージ・PR は英語
- 過去セッションの `.rn/` 配下は読むだけで書き換えない
- レビューは目的に錨を下ろす。1人用 dotfiles。完了基準に照らして効かない指摘は挙げさせない

# Tasks

### #1: 両方のマシンで質問文が読めるか確かめる

**Purpose**: `auto` のままで足りるかを実機で決める。

**Prerequisites**: none

**Steps**:

- [x] Mac で質問を出し、読めるか見てもらう(2026-10-18、読めた)
- [ ] Windows で質問を出し、読めるか見てもらう。読めなければ `claude --debug` で OSC 11 の応答と判定を見る
- [ ] 読めない環境があれば原因を直す(設定か herdr か端末かを、全部の層を見てから決める)

**Completion criteria**:

- 2台それぞれで、質問文と選択肢が読めることをユーザーが確かめている

### #2: PR で Issue が閉じるようにするルールを足す

**Purpose**: Issue #9 のように、PR を merge しても Issue が開いたまま残ることを防ぐ。

**Prerequisites**: none

**Steps**:

- [x] `.claude/rules/pr.md` に `Closes #N` のルールを足す
- [x] この PR の説明に `Closes #13` を書く

**Completion criteria**:

- `.claude/rules/pr.md` に、PR の説明に `Closes #N` を書くルールがある

### #3: Evaluation sign-off

**Purpose**: Acceptance criteria の確認結果をユーザーに承認してもらう。

**Prerequisites**: #1, #2

**Steps**:

- [ ] Acceptance criteria の確認結果をユーザーに提示する
- [ ] `/rn:ty`(承認)または `/rn:gm`(修正 → 対応して再提示)で判断を受ける

**Completion criteria**:

- Acceptance criteria の確認結果がユーザーに承認されている

# State

- **Status**: paused
- **Date**: 2026-10-18
- **Last completed**: #2 Closes ルール
- **Next**: #1 Windows で質問文が読めるかの確認
- **Notes**: branch `worktree-issue-13`、draft PR あり。Windows で読めればコード変更なしで #3 へ進み、PR を ready にする。読めなければ #1 の3つ目のステップから。
