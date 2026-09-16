Rn version: 0.8.0

# Goal

個人用の `CLAUDE.md`(Claude Code にどう働いてほしいかの指示 — 報告の仕方、調査の仕方、
ドキュメントの書き方)を dotfiles で管理し、`./setup.sh` で各マシンの `~/.claude/CLAUDE.md` に
配置する。マシンを移っても同じ指示から始められるようにし、毎回ゼロから指示を与え直すのをやめる。

設計書は作らない(2026-09-10 判断、lovaizu/ccpm#25)。決めることは「既存の `deploy` に 1 ファイル足す」
だけで、それはこの steering に書いてある。

# Acceptance criteria

- clone して `./setup.sh` を実行すると、配置先の `CLAUDE.md` がリポジトリの原本と `diff` 一致する
- 配置は OS 分岐の外(herdr と同じ共通部)で行われ、Mac と WSL の両方で同じ配置先計算が働く
- 配置先は `$HOME/.claude/CLAUDE.md` に固定する。`CLAUDE_CONFIG_DIR` は扱わない(2026-09-10 判断)
- 配置先に既存ファイルがあればバックアップが取られ、そのバックアップ名が既存3つの管理対象の
  バックアップ名と衝突しない
- 配置に失敗した場合は既存の管理対象と同じく FAILURES に載り、run が非ゼロで終わる。成功時は
  何をどこへ置いたか・退避を取ったかが実行時に表示される
- リポジトリの `CLAUDE.md` が、役割 1 文 + 指示 8 行(英語)を持っている。Claude への命令形で
  人間は the user と書く。本文の中身: the user はドラフトの目的と意図を伝え判断する /
  小さく作って実物で裏を取る / 判断は結論・根拠・選択肢と推奨 1 つ / 推測で埋めない /
  会話は日本語・書くものはリポジトリの慣習 / 一般的な語 / 文書は「なぜ」だけ /
  一時ファイルを残さない / 削除は対象を名指しし、変数の有無で範囲が変わる書き方をしない
- README が、この 3 層(CLAUDE.md = 手順にもリポジトリにも依存しない基本指針 / rn などの
  プラグイン = 手順 / スキル = 領域知識)と、行を足すときの判定を持っている
- README が新しい管理対象を意図のレベルで説明し、指示の中身そのものは持たない
- 既存3ファイル(herdr / Windows Terminal / iTerm2)の配置挙動が変わらない

# Assumptions

- Claude Code は `~/.claude/CLAUDE.md` を全プロジェクト共通のユーザー指示として読む。
  `CLAUDE_CONFIG_DIR` で設定ディレクトリを移せるが、このリポジトリでは既定の `$HOME/.claude` だけを
  相手にする
- 現在このマシンに `~/.claude/CLAUDE.md` は存在しない(確認済み)。よって初回配置はバックアップを
  取らない経路を通る
- 持ち運びたい指示の元ネタは、セッション記録 `~/.claude/projects/**/*.jsonl` に残る私自身の
  発言(2026-08-14〜2026-09-07、サブエージェントへの指示と自動通知を除いた 357 件)。memory の
  5 件を元ネタにする案は却下済み(2026-09-06)。抽出した姿勢を plan gate で 6 回改訂し、
  「役割 1 文 + 指示 9 行」に収束した(2026-09-08)。方針: 書いたら負け、前提(役割)から導ける行は
  書かない、見出しを付けない。本文は英語で書く(ユーザー指定)
- 2026-09-12、層で切り直して 9 行から 7 行にした。CLAUDE.md は手順にもリポジトリにも依存しない
  基本指針だけを持ち、手順はプラグイン(rn / aiya)、領域知識はスキルが持つ。落とした 2 行
  「目的を言語化して合意」「最終成果物から逆算して合意」は手順であり、rn の planning-workflow
  step 1 / step 4 と plan gate が合意まで含めて持っていることを確認済み。同じ基準で「レビューの
  依頼の仕方」も CLAUDE.md に入れず、rn 側の lovaizu/ccpm#23 に残す
- 2026-09-12、削除の書き方の 1 行を足して 8 行にした。`rm -rf "$S"/*.out` の形が Claude Code の
  危険検知に掛かり、ユーザーが承認を求められた。承認を求められても危険かどうかを一目で確かめる
  手立てが無いというのがユーザーの判断。検知を settings.json で黙らせる案は、組み込みの検知で
  あって permission ルールではなく、黙らせれば以後すべての同じ形を素通しにするので却下
- memory の仕組みは今回変更しない。CLAUDE.md はマシンをまたいで持ち運びたい指示を持ち、
  memory はこれまで通り動く。両者の重複はいまは許容する
- Issue #9(settings.json / statusline / プラグインの再現)は別セッションの範囲であり、
  今回は触らない

# Rules

- commit and push every change; one completion marker per task
- 設定値・指示の中身は README に書かない。README は意図・規則・手順だけを持つ
- 既存の `deploy` の方式(実体をコピー、丸ごと上書き、dotfiles が正)に乗せる。
  シンボリックリンクは張らない

# Tasks

### #1: (取り下げ) design.md に Claude Code 指示の配置を反映する

2026-09-10 に取り下げ。別セッション `.rn/20260822-herdr4mac/design.md` を編集対象にしていたが、
他セッションの `.rn/` は読むだけで更新しない。今回は記録すべき設計が無いので設計書自体を持たない
(プラグイン側の是正は lovaizu/ccpm#25)。design.md への変更 2 コミットは元に戻した。

### #2: 個人用 CLAUDE.md を書く ✅

**Purpose**: リポジトリに `claude/CLAUDE.md` を作り、マシンをまたいで持ち運びたい汎用の指示を
そこに書く。

**Prerequisites**: none

**Steps**:

- [x] plan gate で合意した本文(英語、役割 1 文 + 指示 9 行)をそのまま `claude/CLAUDE.md` にする
- [x] 手順に属する 2 行を落として 7 行にし、英語の係り受けを 3 箇所直す(意味は変えない)
- [x] 削除の書き方の 1 行を足して 8 行にする(2026-09-12 判断)
- [x] 特定リポジトリの固有名詞が無いことを確認する
- [x] 実機で `~/.claude/CLAUDE.md` を置いた状態で新しいセッションを開き、内容が読まれることを
      確認する
- [x] self-check (OK/NG per completion criterion, record in checks/2.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- 別のマシンで Claude Code を起動したときに、報告の仕方・調査の仕方・ドキュメントの書き方に
  ついて、いま与えている指示と同じ前提が効く
- どの項目も dotfiles リポジトリ固有の事情に依存していない(他のリポジトリで読まれても
  意味をなす)
- 指示が守れなかったときにそれと分かる程度に具体的で、「適切に」「正しく」のような
  判定できない語で書かれていない
- 本文が 9 行(役割 1 文 + 指示 8 行)で、見出しやタイトルが足されていない。plan gate で合意した
  本文から、手順に属する 2 行を落とし、意味を変えない英語の手直しを加え、削除の書き方の 1 行を
  足したものになっている(合意本文との突き合わせ結果は `checks/2.md`、本文自体は履歴 `7957718`)
- どの行も手順の一歩ではなく、特定の領域の知識でもない(手順は rn、領域知識はスキルが持つ)

### #3: setup.sh に配置を追加する ✅

**Purpose**: `claude/CLAUDE.md` を `$HOME/.claude/CLAUDE.md` へ、既存の `deploy` に乗せて配置する。

**Prerequisites**: #2

**Steps**:

- [x] OS 分岐の外、herdr の配置と並べて `deploy` を呼ぶ
- [x] Mac で実行し、初回配置・再実行(Up to date)・既存ファイルがある場合のバックアップ・
      配置先が書けない場合の失敗経路を確認する
- [x] self-check (OK/NG per completion criterion, record in checks/3.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium) — N/A(1行の追加、規模に見合わず)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- 実行後、配置先の `CLAUDE.md` がリポジトリの原本と `diff` 一致する
- 2回目の実行が `Up to date` と表示し、バックアップを増やさない
- 既存ファイルがある状態での実行がバックアップを残し、その名前が既存3つのバックアップと
  衝突しない
- 配置に失敗させた実行が FAILURES に載り、非ゼロで終わる
- 既存3ファイルの配置結果が、この変更の前後で変わらない

### #4: README に管理対象として書く ✅

**Purpose**: README に、個人用 CLAUDE.md を意図のレベルで加える。

**Prerequisites**: #3

**Steps**:

- [x] ~~「設定対象」の表に `claude/CLAUDE.md` の行を足す~~ — 表ごと取り下げ(2026-09-16、PR #12
      レビュー)。管理対象の一覧はリポジトリの構成と `./setup.sh` の実行時表示から読めるので
      README は持たない
- [x] 3 層(CLAUDE.md / プラグイン / スキル)と、行を足すときの判定を README に書く
- [x] 「直す前に」の丸ごと上書きの項が CLAUDE.md にも当てはまることを確認する(必要なら書き足す)
- [x] 指示の中身そのものを README に書いていないことを確認する
- [x] self-check (OK/NG per completion criterion, record in checks/4.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium) — N/A(QA と Craft が事実確認を兼ねた)

**Completion criteria**:

- README だけを読んだ人が、目的・使い方・決まりごとを理解でき、手で直しても次の実行で戻ることが
  分かる。何が管理されどこへ置かれるかは README に持たず、リポジトリの構成と `./setup.sh` の
  実行時表示に委ねる(2026-09-16、PR #12 レビューで変更)
- README に指示の本文・具体的な文言が引き写されていない
- 既存の記述と重複した説明が増えていない

### #5: Evaluation sign-off

**Purpose**: Acceptance criteria を通しで確認し、結果をユーザーに提示して承認を得る。

**Prerequisites**: #4

**Steps**:

- [x] クリーンな状態から `./setup.sh` を実行し、Acceptance criteria を1件ずつ確認する
- [ ] 結果をユーザーに提示し、`/rn:ty`(承認)または `/rn:gm`(修正)の判定を受ける
- [x] `/rn:gm` の場合は指摘に対応して再提示する

**Completion criteria**:

- Acceptance criteria の全項目が、根拠つきで満たされていることが示されている
- ユーザーが承認している

# State

(written by /rn:dn, read and reset to this placeholder by /rn:up. `Status` is `paused` while a
session is suspended — the signal /rn:up and /rn:dn search for — and resets to `not suspended` here,
so only a genuinely suspended session reads `paused`.)

- **Status**: not suspended
- **Date**: YYYY-MM-DD
- **Last completed**: #N description
- **Next**: #N description
- **Notes**: bounded forward pointer — branch/PR, next concrete action, open blockers, user-deferred paths, open questions / pending decisions not yet captured in `design.md`; not a re-narration of the session (that lives in `git log`)
