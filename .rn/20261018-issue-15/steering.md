PR: https://github.com/lovaizu/dotfiles/pull/31

# Goal

Gruvbox のダークとライトを両方使えるようにし、初期値(ダーク)を herdr とターミナルで合わせる(Issue #15)。

いまは herdr だけが `gruvbox-light` に固定され、ターミナルは Gruvbox Dark で、暗い背景の上に明るい背景向けの
色が載って読みにくい。また配色がそれぞれ一つに固定されていて、light で作業する手段がない。

# Acceptance criteria

## Attractive quality

- A1: Dark のとき、herdr の UI がターミナルと同じ Gruvbox Dark で描かれ、未選択の Space 名・区切り線が
  暗い背景向けの色になって読める(いまの未選択名 1.67:1 のような、背景に溶ける文字がない)。選択中の
  Space / Agent 行は背景色で見分けられ、その行の名前も読める
- A2: Windows Terminal・iTerm2 のどちらでも、ターミナル側の手動操作で Gruvbox Light に切り替えられ、
  herdr の UI も Light に揃い、選択行が見分けられる。Dark に戻すのも同じ操作でできる。herdr が揃うのは
  その場でも、付け直したあとでもよい

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
- Fact, decided by the user(2026-10-18): 求めるのは「ダークとライトを使えるようにする」「初期値を合わせる」
  の2点。Windows Terminal で herdr がその場で追従しないことは妨げにならない
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

rn は使わない(`/rn:on` していない)。サインオフは設けず、下の 3 つを直接直し、実機で確かめてから報告する
(2026-10-18 ユーザー判断)。

- [x] `herdr/config.toml`: `gruvbox-light` 固定をやめ、`auto_switch = true`、基準は `gruvbox`。
  `[theme.custom.dark]` に `active_row_bg = "#504945"`、`[theme.custom.light]` に `"#d5c4a1"`
- [x] `iterm2/`: light 配色の 2 つ目の動的プロファイル(既定にはしない、それ以外は `herdr` と同じ)
- [x] `README.md`: テーマの不一致を意図とする項目を消す
- [x] 実機確認: Mac で herdr が Dark で揃うこと、Change Profile で Light に揃うこと、`./setup.sh` が通ること

# State

- **Next**: PR の説明を書いた。Ready にするかはユーザー判断
- **Notes (setup)**: このブランチが main (#32) より古いまま `./setup.sh` を流し、`~/.claude/CLAUDE.md` が1行戻った。バックアップから戻し、main をマージ済み
- **Checked (2026-10-18, Mac)**: ユーザーが目で確認。Dark で揃う、`herdr light` に Change Profile で Light に揃う、Light でも ctrl+cmd のキーが効く。Dark へ戻すのは未確認(ユーザーが不要と判断)
- **Notes**: Windows 機の herdr の版と、Windows で付け直して Light に揃うかは未確認。Windows 機はここにない
