Rn version: 0.8.0
Design: .rn/20260822-herdr4mac/design.md

# Goal

個人用の `CLAUDE.md`(Claude Code にどう働いてほしいかの指示 — 報告の仕方、調査の仕方、
ドキュメントの書き方)を dotfiles で管理し、`./setup.sh` で各マシンの `~/.claude/CLAUDE.md` に
配置する。マシンを移っても同じ指示から始められるようにし、毎回ゼロから指示を与え直すのをやめる。

# Acceptance criteria

- clone して `./setup.sh` を実行すると、配置先の `CLAUDE.md` がリポジトリの原本と `diff` 一致する
- 配置は OS 分岐の外(herdr と同じ共通部)で行われ、Mac と WSL の両方で同じ配置先計算が働く
- `CLAUDE_CONFIG_DIR` が絶対パスで設定されていればそこを基点に配置する。相対パスなら無視して
  既定(`$HOME/.claude`)を使い、無視したことを警告する(既存の XDG の扱いと一致する)
- 配置先に既存ファイルがあればバックアップが取られ、そのバックアップ名が既存3つの管理対象の
  バックアップ名と衝突しない
- 配置に失敗した場合は既存の管理対象と同じく FAILURES に載り、run が非ゼロで終わる。成功時は
  何をどこへ置いたか・退避を取ったかが実行時に表示される
- リポジトリの `CLAUDE.md` が、これまでのセッション記録(`~/.claude/projects/**/*.jsonl`)に
  現れた私の姿勢・考え方(目的から判断する / 結論と根拠だけ報告する / 平易な語を使う / 本質に
  削る / 意図は聞き実装は任せる / 調べてから言う / 文書は意図と決定だけ / ゴミを残さない /
  レビューは目的に錨 / 学びを記録する)を、特定リポジトリ固有でない指示として持っている
- README が新しい管理対象を意図のレベルで説明し、指示の中身そのものは持たない
- `.rn/20260822-herdr4mac/design.md` が新しい管理対象を反映している(Claude Code を対象外とする
  記述の解除、構成要素、新しい 4.N)
- 既存3ファイル(herdr / Windows Terminal / iTerm2)の配置挙動が変わらない

# Assumptions

- Claude Code は `~/.claude/CLAUDE.md` を全プロジェクト共通のユーザー指示として読む。
  `CLAUDE_CONFIG_DIR` が設定されている場合はその下を設定ディレクトリとする(未検証 — タスク中に
  実機で確認する)
- 現在このマシンに `~/.claude/CLAUDE.md` は存在しない(確認済み)。よって初回配置はバックアップを
  取らない経路を通る
- 持ち運びたい指示の元ネタは、セッション記録 `~/.claude/projects/**/*.jsonl` に残る私自身の
  発言(2026-08-14〜2026-09-07、サブエージェントへの指示と自動通知を除いた 357 件)。memory の
  5 件を元ネタにする案は却下済み(2026-09-06)。抽出した姿勢は plan gate で提示した草案の
  とおりで、各項目は発言の引用を根拠に持つ
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

### #1: design.md に Claude Code 指示の配置を反映する

**Purpose**: `.rn/20260822-herdr4mac/design.md` を、Claude Code のユーザー指示を管理対象に含む
構造として更新する。

**Prerequisites**: none

**Steps**:

- [ ] 既存 design.md を通読し、今回の作業が変える h3 を特定する
- [ ] 1.4 の「Claude Code のユーザー設定も対象外」を、今回取り込む範囲(個人用 CLAUDE.md)と
      残る対象外(Issue #9 の設定・プラグイン)に書き分ける
- [ ] 3.2 の構成要素に `claude/CLAUDE.md` を加える
- [ ] 新しい 4.N を追加し、配置先の決定(`CLAUDE_CONFIG_DIR` の扱い)・OS 共通部に置く理由・
      バックアップ名が衝突しないことを、決定と理由で書く
- [ ] 5.2 に、memory と CLAUDE.md の重複を許容した判断を書く
- [ ] self-check (OK/NG per completion criterion, record in checks/1.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)
- [ ] Design expert review (subagent)

**Completion criteria**:

- design.md を読んだ第三者が、個人用 CLAUDE.md がどこへ何を根拠に配置されるかを、
  setup.sh を読まずに説明できる
- 1.4 に「Claude Code のユーザー設定は対象外」と、今回それを扱うことが同時に書かれている状態が
  ない(記述の食い違いが残っていない)
- 既存の 4.1〜4.7 のうち、今回の作業が変えない節の本文が変わっていない
- 新設した節が、他の管理対象の節と同じ「何を保証し、破れをどう検知するか」の形で書かれている

### #2: 個人用 CLAUDE.md を書く

**Purpose**: リポジトリに `claude/CLAUDE.md` を作り、マシンをまたいで持ち運びたい汎用の指示を
そこに書く。

**Prerequisites**: #1

**Steps**:

- [ ] plan gate で承認された草案(セッション記録から抽出した姿勢)を出発点にする
- [ ] `claude/CLAUDE.md` を書く。各項目は「何をするか」と「なぜか」を持ち、特定リポジトリの
      固有名詞に依存しない
- [ ] 実機で `~/.claude/CLAUDE.md` を置いた状態で新しいセッションを開き、内容が読まれることを
      確認する(`CLAUDE_CONFIG_DIR` の扱いを含む)
- [ ] self-check (OK/NG per completion criterion, record in checks/2.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- 別のマシンで Claude Code を起動したときに、報告の仕方・調査の仕方・レビューの回し方・
  ドキュメントの書き方について、いま与えている指示と同じ前提が効く
- どの項目も dotfiles リポジトリ固有の事情に依存していない(他のリポジトリで読まれても
  意味をなす)
- 指示が守れなかったときにそれと分かる程度に具体的で、「適切に」「正しく」のような
  判定できない語で書かれていない

### #3: setup.sh に配置を追加する

**Purpose**: `claude/CLAUDE.md` を `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md` へ、既存の
`deploy` に乗せて配置する。

**Prerequisites**: #2

**Steps**:

- [ ] 配置先の基点を決める処理を追加する(絶対パス以外は無視して警告 — 既存 `set_xdg_base` の
      扱いに揃える)
- [ ] OS 分岐の外、herdr の配置と並べて `deploy` を呼ぶ
- [ ] Mac で実行し、初回配置・再実行(Up to date)・既存ファイルがある場合のバックアップ・
      配置先が書けない場合の失敗経路を確認する
- [ ] 相対パスの `CLAUDE_CONFIG_DIR` を与えて、警告が出て既定へ配置されることを確認する
- [ ] self-check (OK/NG per completion criterion, record in checks/3.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- 実行後、配置先の `CLAUDE.md` がリポジトリの原本と `diff` 一致する
- 2回目の実行が `Up to date` と表示し、バックアップを増やさない
- 既存ファイルがある状態での実行がバックアップを残し、その名前が既存3つのバックアップと
  衝突しない
- 配置に失敗させた実行が FAILURES に載り、非ゼロで終わる
- 既存3ファイルの配置結果が、この変更の前後で変わらない

### #4: README に管理対象として書く

**Purpose**: README の設定対象表と手順に、個人用 CLAUDE.md を意図のレベルで加える。

**Prerequisites**: #3

**Steps**:

- [ ] 「設定対象」の表に `claude/CLAUDE.md` の行を足す
- [ ] 「直す前に」の丸ごと上書きの項が CLAUDE.md にも当てはまることを確認する(必要なら書き足す)
- [ ] 指示の中身そのものを README に書いていないことを確認する
- [ ] self-check (OK/NG per completion criterion, record in checks/4.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- README だけを読んだ人が、何が管理されどこへ置かれるかと、手で直しても次の実行で戻ることを
  理解できる
- README に指示の本文・具体的な文言が引き写されていない
- 既存の記述と重複した説明が増えていない

### #5: Evaluation sign-off

**Purpose**: Acceptance criteria を通しで確認し、結果をユーザーに提示して承認を得る。

**Prerequisites**: #4

**Steps**:

- [ ] クリーンな状態から `./setup.sh` を実行し、Acceptance criteria を1件ずつ確認する
- [ ] 結果をユーザーに提示し、`/rn:ty`(承認)または `/rn:gm`(修正)の判定を受ける
- [ ] `/rn:gm` の場合は指摘に対応して再提示する

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
