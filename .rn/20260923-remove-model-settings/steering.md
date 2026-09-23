Rn version: 0.8.0

# Goal

Claude Code を、モデルごとの既定のモデルと effort で動かす(Issue #22)。いまの
`claude/settings.json` は `model` と `effortLevel` を固定しているが、どちらもこの意図に沿わない。

- `effortLevel` は、Opus 5.5 以降のモデルではユーザー設定の最上位にあっても無視される。ファイルを
  読むと high で動いているように見えるが、実際はモデルの既定で動いている — 読み手が逆の結論に至る。
- `model` は Opus 系に固定している。いまは外しても既定が同じなので挙動は変わらず、外すことで将来の
  既定の変更に上書きせず追随できるようになる。

`/effort` や `/model` で選んだ値は `~/.claude/settings.json` に書き込まれ、次の `./setup.sh` で
repo の状態に戻る — これはこの repo の他の設定と同じ振る舞いで、変える対象ではない。

# Acceptance criteria

- repo の `claude/settings.json` が `model` も `effortLevel` も持たない。他のキーとその値は変わらない
- `./setup.sh` を流したあとの `~/.claude/settings.json` が `model` も `effortLevel` も持たず、
  Claude Code が設定エラーを出さずに起動する
- `/effort` や `/model` で書き込まれた `model` / `effortLevel` が、次の `./setup.sh` で消える
- statusline が、`model` / `effortLevel` を設定していない状態でもモデル名と effort を表示する
  (effort はモデルの既定値が表示される)
- repo の中に、モデルや effort を固定していると読める記述(README・設定ファイルのコメント等)が
  残っていない。過去セッションの `.rn/` は当時の記録なので対象外

# Assumptions

- `effortLevel` は Opus 5.5 以降で無視され、`model` 未設定時の既定は Opus 5.5 — Issue #22 が
  https://code.claude.com/docs/en/model-config を根拠に書いている。**未検証**
- `./setup.sh` は `claude/settings.json` を丸ごと置き換える(`setup.sh` の `deploy` 呼び出し。
  Issue #9 で検証済み)ので、repo から消したキーはマシンからも消える
- statusline の effort 表示は Claude Code が stdin に渡す `.effort.level` を読んでおり、
  `effortLevel` 設定には依存しない(`claude/scripts/statusline.sh` のコードから。実データでは未確認)

# Rules

- commit and push every change; one completion marker per task
- 会話・ドキュメントは日本語(コード・コミットメッセージは英語)
- 過去セッションの `.rn/` 配下は読むだけで書き換えない
- レビューは目的に錨を下ろす。1人用 dotfiles で、変更は設定2行の削除。完了基準に照らして効かない
  指摘は挙げさせない

# Tasks

### #1: `claude/settings.json` から `model` と `effortLevel` を外し、既定で動くことを確かめる

**Purpose**: repo の設定からモデルと effort の固定をなくし、`./setup.sh` 後の Claude Code が
モデルごとの既定で動く状態にする。

**Prerequisites**: none

**Steps**:

- [x] `claude/settings.json` から `model` と `effortLevel` の2キーを削除する
- [x] repo 内に他の固定記述がないか確認する(過去セッションの `.rn/` は除く)
- [x] `./setup.sh` を流し、`~/.claude/settings.json` が repo と一致することを確認する
- [x] 新しい Claude Code セッションで、設定エラーがなく、モデルと effort が既定値であること、
      statusline にモデル名と effort が表示されることを確認する
- [x] `/effort` で値を選んで `~/.claude/settings.json` に書き込ませ、`./setup.sh` で消えることを確認する
- [x] self-check (OK/NG per completion criterion, record in checks/1.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- repo の `claude/settings.json` に `model` と `effortLevel` のキーが無く、それ以外のキーと値は
  変更前と同一で、JSON として読める
- `./setup.sh` 後の `~/.claude/settings.json` に `model` と `effortLevel` が無く、`./setup.sh` が
  失敗を報告せずに終わる
- `./setup.sh` 後に起動した Claude Code が設定エラーを出さず、使うモデルと effort がそのモデルの
  既定値になっている(Opus 5.5 なら effort は medium)
- statusline がモデル名と effort を表示し、jq エラー等で表示が欠けない
- `/effort` で書き込まれた値が、次の `./setup.sh` 後の `~/.claude/settings.json` に残っていない
- repo 内(過去セッションの `.rn/` を除く)に、モデルや effort を固定していると読める記述が無い

### #2: Evaluation sign-off

**Purpose**: Acceptance criteria の確認結果をユーザーに承認してもらう。

**Prerequisites**: #1

**Steps**:

- [ ] Acceptance criteria の確認結果をユーザーに提示する
- [ ] `/rn:ty`(承認)または `/rn:gm`(修正 → 対応して再提示)で判断を受ける

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
