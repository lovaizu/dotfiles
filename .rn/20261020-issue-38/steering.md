# Goal

rn の作り直し(lovaizu/ccpm#54)が終わるまで、このリポジトリを apply すると rn と writ が入っていない状態になる(Issue #38)。
いまは `home/run_after_ccpm-plugin.sh.tmpl` が apply のたびに `rn@ccpm` を入れるので、手で消しても次の apply で戻る。
#24 でサンドボックス起動ごとに apply するようになると、起動のたびに戻る。
turn も rn の作り直しが終わるまで使わないので、同じく外す(2026-10-20、ユーザーの判断)。

# Acceptance criteria

- apply は rn も writ も turn も入れない
- rn・writ・turn が入っているマシンで apply すると、どれも消える
- 入っていないマシンで apply しても失敗にならず、何も変えない
- 作り直した rn が出たとき、apply で rn と turn が入り writ は入らない状態に、スクリプトの対象を書き換えるだけで移れる
- ccpm 以外のプラグインとマーケットプレイスには触らない

# Assumptions

- Fact(このマシンで確認、2026-10-20): `claude plugin uninstall` は入っていないプラグインに対して exit 1 で失敗する。
  なので `claude plugin list --json` で入っているかを見てから消す
- Fact(同): いまこのマシンには `rn@ccpm`・`writ@ccpm` は入っていない(手で消した状態)。`turn@ccpm` は入っている(#3 で消した)
- Fact(同): `rn@synced`(scope synced)が一覧に出る。このリポジトリが入れたものではない

# Rules

- commit and push every change
- 会話・`.rn/` は日本語。コード・コミット・PR は英語
- 過去セッションの `.rn/` は読むだけで書き換えない
- README は変えない(読み手が見落として誤る点が増えないため)
- レビューは目的に照らして効く指摘だけ。1人用 dotfiles

# Tasks

### #1: apply で rn・writ を消し、入れない

- [x] スクリプトを「入れるもの」「消すもの」の2つの一覧にし、いまは入れるもの無し・消すもの rn と writ にする
- [x] このマシンで rn・writ を入れてから apply し、両方が消え turn が残ることを確かめる
- [x] もう一度 apply し、何も変えずに成功することを確かめる
  - 2026-10-20: rn を入れて writ が依存として付いた状態で `./setup.sh` を流し、rn・writ が消え turn・figma は残った。
    2回目はプラグインについて何も出さず exit 0

### #2: PR を仕上げる

- [ ] PR 本文に確認の結果(turn を含む)を書き、レビューに出す

### #3: turn も消す

- [x] 消すものに turn を加える
- [x] このマシンで turn が入った状態から apply し、turn が消え figma が残ることを確かめる
- [x] もう一度 apply し、何も変えずに成功することを確かめる
  - 2026-10-20: 1回目で turn が消え figma は残った。2回目はプラグインについて何も出さず exit 0

# State

- **Status**: not suspended
- **Next**: #2 — PR #39 をレビューに出してよいか、ユーザーに聞く
- **Notes**: draft PR #39。`rn@synced`(claude.ai から同期されるプラグイン)はユーザーが claude.ai で消し、
  残っていたフォルダと settings.json の `"rn@synced": false` も消した(2026-10-20、このリポジトリの外の作業)。
  プッシュと gh は `cc`(`~/.config/kiyobot.env` を読む)で起動したセッションで行う
