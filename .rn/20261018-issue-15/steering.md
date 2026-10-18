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
UI 全体を反転させずに選択を見分けられる。また、いまは herdr・iTerm2・Windows Terminal がそれぞれ一つの
配色に固定され、どちらの機械でも light で作業する手段がないので、それを作る。

# Acceptance criteria

## Attractive quality

- A1: Dark のとき、herdr の UI がターミナルと同じ Gruvbox Dark で描かれ、未選択の Space 名・区切り線が
  暗い背景向けの色になって読める(いまの未選択名 1.67:1 のような、背景に溶ける文字がない)。選択中の
  Space / Agent 行は背景色で見分けられ、その行の名前も読める
- A2: Windows Terminal・iTerm2 のどちらでも、ターミナル側の手動操作だけで Gruvbox Light に切り替えられ、
  herdr の UI も Light に揃い、選択行が見分けられる。Dark に戻すのも同じ操作でできる

## Must-be quality

- M1: `./setup.sh` は従来どおり Dark を基準として配置する(切り替えの状態は保存しない)
- M2: iTerm2 の既定プロファイルは従来の `herdr`(setup.sh が確かめる GUID)のまま。キー割り当て
  (ctrl+cmd 系)は追加のプロファイルでも同じに効く
- M3: OS の外観設定(ライト/ダーク)には触れず、それに左右されない
- M4: README のうち、テーマの不一致を意図だと説明する項目は消える
- M5: 両方の機械の herdr が、`[theme.custom.light]` / `[theme.custom.dark]` を読める版(0.9.0 以上)で
  動く。古い版では設定ファイルごと読めなくなる

# Assumptions

- Fact, `herdr --version` をこのマシンで実行(2026-10-18): herdr 0.9.1。Issue が前提とする 0.9.0 以上を
  満たす
- Fact, `windows-terminal/settings.json` を読んで確認: `Gruvbox Dark` と `Gruvbox Light` の両スキームが
  定義済みで、全プロファイルが継承する `profiles.defaults.colorScheme` が `Gruvbox Dark`(各プロファイルは
  上書きしていない)
- Fact, `lib/tools.sh` を読んで確認: setup.sh は herdr が入っていれば更新しない
- Assumption: Windows 機(WSL)の herdr の版は未確認
- Fact, Issue #15 より(0.8.2 で検証済みと記載): herdr は OS ではなくターミナルの color-scheme 変更通知で
  テーマを切り替え、再起動は要らない
- Fact, Issue #15 より(ユーザーが決定): 選択行の色は Dark で `#504945`、Light で `#d5c4a1`。今より弱い
  ハイライトになることは承知のうえ
- Fact, iTerm2 のソース(gnachman/iTerm2 `PTYSession.m` の `textViewBackgroundColorDidChangeFrom:to:`)を
  読んで確認(2026-10-18、このマシンは iTerm2 3.7.4): 背景色の明暗が変わると、きっかけを問わず(Change
  Profile を含む)mode 2031 を有効にしたアプリへ `CSI ? 997 ; 1|2 n` を送る。明暗は背景色から判定する
- Fact, microsoft/terminal#18375 が未解決(2026-10-18 確認): Windows Terminal は mode 2031 の変更通知を
  送らない。手動でスキームを変えても herdr は前のテーマのまま。Issue #15 は確かめる点として「送らなければ
  付け直すまで前のテーマ」と書いている
- Fact, microsoft/terminal の OSC 11 応答に関する issue(#19904 など)より: Windows Terminal は背景色の問い
  合わせ(OSC 11)に答える
- Assumption: herdr は attach のたびに OSC 11 で背景色を問い合わせ、その明暗でテーマを選ぶ(バイナリに
  OSC 11 の問い合わせ文字列があることだけ確認。付け直しで追従するか、WSL 越しに応答が届くかは未検証)

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
- 古い herdr をどう 0.9.0 以上にするか(setup.sh で `herdr update` するか、手作業として伝えるか)
- 手動切り替えの具体的な操作: Windows Terminal は設定画面の配色(settings.json を書き換え、次の
  `./setup.sh` で戻る)か保存しない一時変更か、iTerm2 は Change Profile をどこから呼ぶか
- README のテーマ不一致の項目を消すこと、切り替え方を README に書くかどうか(`.claude/rules/readme.md`
  に従って判断する)
- 同じ herdr に複数のクライアントが付くときのテーマの扱い
- 両ターミナルで手動切り替え時に herdr が追従するかを実機で確かめる
