---
rn: 0.9.0
pr: https://github.com/lovaizu/dotfiles/pull/31
status: running
artifact-language: English (code, commits, README, PR); the `.rn/` record in Japanese, as .claude/rules/language.md sets
conversation-language: Japanese
readme: README.md
design: docs/design.md
verification: docs/verification.md
---

# Goal

herdr の UI テーマをターミナルと同じ Gruvbox の明暗に揃え、Windows と Mac の両方で Gruvbox Light と Dark を
ターミナル側の手動切り替えで使えるようにする(Issue #15)。

いまは herdr だけが `gruvbox-light` に固定され、ターミナルは Gruvbox Dark。選択中の Space 行を目立たせる
ためだったが、それ以外の UI は暗い背景の上に明るい背景向けの色で描かれ、未選択の Space 名は背景に対して
1.67:1 しかなく読みにくい。herdr に選択行の色を直接決める `[theme.custom] active_row_bg` ができたので、
UI 全体を反転させずに選択を見分けられる。あわせて、明るい環境で作業したいときに light を選べる道を作る。

# Acceptance criteria

## Attractive quality

- A1: Dark のとき、herdr の UI 全体(未選択の Space 名・区切り線を含む)がターミナルの暗い背景の上で
  読め、選択中の Space / Agent 行が色で見分けられる
- A2: Windows Terminal・iTerm2 のどちらでも、ターミナル側の手動操作だけで Gruvbox Light に切り替えられ、
  herdr の UI も Light に揃い、選択行が見分けられる。Dark に戻すのも同じ操作でできる

## Must-be quality

- M1: `./setup.sh` は従来どおり Dark を基準として配置する(切り替えの状態は保存しない)
- M2: iTerm2 の既定プロファイルは従来の `herdr`(setup.sh が確かめる GUID)のまま。キー割り当て
  (ctrl+cmd 系)は追加のプロファイルでも同じに効く
- M3: OS の外観設定(ライト/ダーク)には触れず、それに左右されない
- M4: README のうち、テーマの不一致を意図だと説明する項目は消える

# Assumptions

- Fact, `herdr --version` をこのマシンで実行(2026-10-18): herdr 0.9.1。Issue が前提とする 0.9.0 以上を
  満たす
- Fact, `windows-terminal/settings.json` を読んで確認: `Gruvbox Dark` と `Gruvbox Light` の両スキームが
  定義済みで、既定プロファイルは `Gruvbox Dark`
- Fact, Issue #15 より(0.8.2 で検証済みと記載): herdr は OS ではなくターミナルの color-scheme 変更通知で
  テーマを切り替え、再起動は要らない
- Fact, Issue #15 より(ユーザーが決定): 選択行の色は Dark で `#504945`、Light で `#d5c4a1`。今より弱い
  ハイライトになることは承知のうえ
- Assumption: iTerm2 の Change Profile と Windows Terminal の手動スキーム変更で、ターミナルが color-scheme
  変更通知を herdr に送る(未検証。送らなければ herdr は再アタッチまで前のテーマのまま)
- Assumption: Windows Terminal で `Gruvbox Light` を選んだとき、ターミナルが自分を light と報告する
  (スキームの背景色から判定されるかは未検証)

# Rules

- commit and push every change
- コード・コメント・コミットメッセージ・README・PR は英語、`.rn/` の記録と会話は日本語
- 過去セッションの `.rn/` 配下は読むだけで書き換えない
- README には意図だけを書き、設定値(色・テーマ名)は書かない(`.claude/rules/readme.md`)
- 設定ファイルには動かない値だけを置く(`.claude/rules/config.md`)
- レビューは目的に錨を下ろす。1人用 dotfiles・2台・`./setup.sh` は年に数回手で流す。完了基準に効かない
  指摘は挙げさせないが、それを直さない理由にはしない(`.claude/rules/review.md`)

# Tasks

### [ ] #1: Plan sign-off
### [ ] #2: Design sign-off

# Not yet specified

- herdr `config.toml` の `[theme]` を auto_switch にし、`[theme.custom.light]` / `[theme.custom.dark]` に
  選択行の色を置く
- iTerm2 に light 配色の 2 つ目の動的プロファイルを足す(既定ではない、キー割り当ては同じ)
- README のテーマ不一致の項目を消す
- 両ターミナルで手動切り替え時に herdr が追従するかを実機で確かめる
