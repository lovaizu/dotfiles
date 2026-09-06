Rn version: 0.8.0
Design: .rn/20260906-issue-9/design.md

# Goal

この dotfiles が端末環境に対してやっていること — 「clone して `./setup.sh` を実行すれば、Win
(WSL + Windows Terminal)と Mac(iTerm2)で同じ状態になる」— を、その端末の中で毎日使う
Claude Code のユーザー設定にも広げる(Issue #9)。いまは端末だけが両OSで揃い、その中で動くものは
マシンごとに手で設定し直している。

対象は Claude Code の**ユーザー設定**: `~/.claude/settings.json` と、それが `statusLine` から
参照する `~/.claude/scripts/statusline.sh`。`settings.json` の `enabledPlugins` /
`extraKnownMarketplaces` は宣言であって実体を入れないので(Issue #9 のコメントで隔離 `$HOME` に
おいて実測済み)、`claude plugin marketplace add` / `claude plugin install` の実行までを
`setup.sh` に含めて初めて「手で設定しない」が成り立つ。

**Claude Code の指示書(`CLAUDE.md` / 出力スタイル)は対象外** — Issue #10 として別に立っている。
端末環境そのもの(herdr / iTerm2 / Windows Terminal)の設定内容にも手を入れない。

# Acceptance criteria

- `~/.claude/settings.json` と `~/.claude/scripts/statusline.sh` が dotfiles の管理対象になっており、
  `./setup.sh` の実行後、配置先が repo の原本と `diff` で一致する。同じ dotfiles で2回流しても
  バイト列は変わらない。この2つは OS 共通で、mac でも WSL でも同じ場所(`$HOME/.claude/…`)へ配る
- **配置方式は増えない**。Claude Code の設定も既存の管理対象(herdr / iTerm2 / WT)と同じ
  「丸ごと上書き・dotfiles が正」の1方式で配られ、ファイルごとの例外を持たない。Claude Code 自身が
  書き戻した値(`theme` / `model` / `effortLevel` など)は次の `./setup.sh` で dotfiles の値に戻る
- **退避が管理対象ごとに見分けられる**。`BACKUP_DIR` に退避された Windows Terminal の
  `settings.json` と Claude Code の `settings.json` が、退避先の path だけでどちらのものか判別できる
  (WSL では両方が同じ run で配られる)。design.md §4.6 が置いた「管理対象の basename は互いに違う」
  という規則が、今回の追加後も成り立っているか、成り立たせ方が置き換わっているかのどちらかである
- **プラグインの実体が入る**。`claude` コマンドのあるマシンで `./setup.sh` を流したあと、
  `claude plugin list` が `settings.json` の `enabledPlugins` にあるプラグインを enabled として
  列挙する。すでに入っているマシンで再実行してもエラーにならず、run は exit 0 で終わる(冪等)。
  `claude` コマンドが無いマシンでは run は失敗にならない
- **herdr が所有するファイルは管理対象にしない**。`~/.claude/hooks/herdr-agent-state.sh` は
  herdr の integration が書き、更新のたびに上書きすると自分で宣言しているファイルなので、
  dotfiles は原本を持たない。`settings.json` はそのフックを参照したまま配られるので、
  そのファイルが無いマシンで run が読み手に何を求めるか(`warn` で Fix を出す / 何も言わない)が
  決まっており、そのとおりに振る舞う
- **秘密とマシン固有値を持ち込まない**。repo に置く `settings.json` に、資格情報・トークン・
  そのマシンでしか意味を持たない絶対パスが含まれない(`$HOME` 展開で書けるものは `$HOME` で書く)
- 配置に失敗した run の扱いが既存のまま保たれている: 警告を出して残りの配置を続行し、最後に
  失敗を列挙して非0で終わる。`Done.` は全部配置できた run だけが出す
- README が**再現に要るものだけ**を追記している — (a) 設定対象(何をどのファイルが持つか)、
  (b) 設定ファイルを素直に読むと欠陥に見えるが意図している点、(c) `setup.sh` が実行できず人が
  やるしかない手順。**具体的な設定値は書かない**(モデル名・テーマ名・プラグイン名・statusline の
  表示内容はすべて設定ファイル側にしか置かない)。`setup.sh` が実行時に表示する内容も置かない
- `steering.md` / `design.md` / `setup.sh` / README が同じことを言っている

# Assumptions

- **Claude Code は両OSとも WSL / macOS 側の shell で動く**。Win では herdr が WT の WSL プロファイル
  の中で動き、その中で Claude Code が起動するので、`$HOME/.claude` は WSL 側の HOME を指す。
  よって配置先に OS 別の分岐は要らない。**WSL 実機では未検証の仮定**(`statusline.sh` 冒頭の
  コメントが「macOS /bin/sh と WSL の dash の両方で動く」と書いていることが傍証)
- `~/.claude/settings.json` は Claude Code 自身が書き戻す — 対話中にファイルの mtime が更新される
  ことを実測。herdr の `config.toml` や WT の `settings.json` と同じ「アプリも書くが dotfiles が正」
  の関係になる
- `statusline.sh` は `settings.json` から `sh "$HOME/.claude/scripts/statusline.sh"` として
  起動されるので、配置先に実行ビットは要らない。`cp` が新規作成先に元のモードを写すことも実測済み
- プラグインの導入は公開 marketplace であればログイン不要 — 隔離 `$HOME` で
  `claude plugin marketplace add lovaizu/ccpm` → `claude plugin install rn@ccpm` が通ることを
  Issue #9 のコメントで実測済み。**非公開 marketplace はこの前提の外**
- `settings.json` の `outputStyle` / `theme` の現在値(`Concise` / `light`)は Claude Code 組み込みの
  もので、`~/.claude/output-styles/` や `~/.claude/themes/` にあるファイルには依存しない — よって
  それらのディレクトリは今回の管理対象に入らない(カスタム出力スタイルは Issue #10 側の話)
- **マシンは mac 1台と Windows 1台**。既存の設定と同じく、丸ごと上書きが成り立つのはこの前提の下だけ

# Rules

- commit and push every change; one completion marker per task
- 会話・ドキュメントは日本語(コード・コミットメッセージは英語)
- **レビューは目的に錨を下ろす**。この dotfiles は1人用で、mac 1台と Windows 1台、`setup.sh` は
  対話的に年数回流すだけ、配置が失敗すれば端末を触った瞬間に分かる。レビューを回すときは依頼文に
  この利用状況を書き、「完了基準に照らして効かない指摘は挙げるな」を明示する。回す軸の数と周回数も
  ここから決める — 毎回フルセットにしない
- 端末環境そのものの設定(`herdr/config.toml` / `iterm2/herdr.json` /
  `windows-terminal/settings.json`)の**中身には手を入れない**。触るのは `setup.sh` の機構と、
  退避の名前空間の衝突を解くために必要な範囲だけ
- `setup.sh` の既存の機構(終端番兵 `REACHED_END`、`HOME` の入口ガード、XDG 値の絶対パス検査、
  `deploy` が常に 0 を返す規約、大文字/小文字の命名規則)を壊さない — いずれも
  design.md §4.6 が exit 0 の意味を支えるために置いたもの
- このファイルと `design.md`、`checks/` は**常に最新状態に保つ**。変更履歴・撤回した内容の手順・
  実施済みレビューのチェックボックスは残さない — それらは git log と成果物から辿れる。
  残すのは「なぜそうしたか」と、決定に紐づくレビュー指摘・対応要否・対応内容

# Tasks

### #1: 設計を決めて design.md に書く

**Purpose**: Claude Code のユーザー設定を既存の配置機構に載せるための設計 — 何を管理対象にするか、
退避の名前空間の衝突をどう解くか、プラグイン導入という「配置ではない動作」を `setup.sh` の
どこに位置づけるか — を決めて `.rn/20260906-issue-9/design.md` に書く。

**Prerequisites**: none

**Steps**:

- [ ] `~/.claude/settings.json` の各キーを「dotfiles で固定するもの / マシン側に委ねるもの /
      秘密」に仕分ける
- [ ] 退避の名前空間の衝突(WT と Claude Code の `settings.json` が同じ basename)の解き方を決める
- [ ] プラグイン導入(`claude plugin marketplace add` / `install`)の位置づけ — 失敗は
      `record_failure` / `warn` / 素の `echo` のどれか、冪等性はどう担保するかを決める
- [ ] herdr 所有の `herdr-agent-state.sh` を管理対象にしない判断と、それが無いマシンでの通知を決める
- [ ] design-template.md の5節すべてに decision + reasoning で答える
- [ ] self-check(OK/NG per completion criterion, record in checks/1.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)
- [ ] Design expert review (subagent)

**Completion criteria**:

- `design.md` が、Claude Code の設定を配置するために `setup.sh` が持つ機構を、既存の1方式に
  対してどう足す/変えるかを述べており、その理由が読み取れる。h3 の問いに未回答のものが無い
- 退避の名前空間の衝突について、解いた形と、それが既存の管理対象(herdr / iTerm2 / WT)の退避先を
  どう変えるかが書かれている。「basename は互いに違う」という既存規則を保つのか置き換えるのかが
  曖昧でない
- プラグイン導入が「配置ではない動作」であることを踏まえた位置づけが書かれており、
  `claude` コマンドが無いマシン・すでに導入済みのマシン・導入に失敗したマシンの3つで
  run がどう終わるかがそれぞれ決まっている
- repo に置く `settings.json` に含めないと決めたキーがあれば、その理由が書かれている
- 決めていないことを決めたように書いていない — 未検証の仮定は仮定として名指しされている

### #2: Design sign-off

**Purpose**: `design.md` の設計をユーザーに提示し、実装に入る前に承認を取る。

**Prerequisites**: #1

**Steps**:

- [ ] `design.md` をユーザーに提示する
- [ ] `/rn:ty`(承認)または `/rn:gm`(修正 → 指摘に対応して再提示)で判定を受ける

**Completion criteria**:

- `design.md` が承認されている

### #3: Claude Code 設定の原本を repo に取り込む

**Purpose**: いまのマシンの `~/.claude/settings.json` と `~/.claude/scripts/statusline.sh` を、
#1 の仕分けに従って repo の原本にする。

**Prerequisites**: #2

**Steps**:

- [ ] `settings.json` を #1 で決めた形(固定するキーだけ)で repo に置く
- [ ] `statusline.sh` を repo に置く
- [ ] 原本が秘密とマシン固有の絶対パスを含まないことを確認する
- [ ] self-check(OK/NG per completion criterion, record in checks/3.md)

**Completion criteria**:

- repo の `settings.json` が有効な JSON で、Claude Code が読める形になっている
  (配置して Claude Code を起動しても設定エラーにならない)
- 原本に資格情報・トークン・そのマシンでしか意味を持たない絶対パスが含まれていない
- repo の `statusline.sh` が、いまのマシンで動いているものと同じ出力を返す
  (同じ入力 JSON を流して出力が一致する)
- #1 で「含めない」と決めたキーが原本に残っていない

### #4: setup.sh に Claude Code 設定の配置を足し、退避の名前空間の衝突を解く

**Purpose**: 既存の `deploy` を使って2ファイルを OS 共通部から配り、同名 basename の退避が
見分けられない問題を #1 の設計どおりに解く。

**Prerequisites**: #3

**Steps**:

- [ ] 退避先の決め方(`backup_path_for`)を #1 の設計どおりに変える
- [ ] OS 共通部に Claude Code の2ファイルの `deploy` を足す
- [ ] herdr 所有フックが無いマシンでの通知を #1 の設計どおりに足す
- [ ] 隔離した `$HOME` で実測する(初回配置 / 再実行の冪等性 / 既存ファイルからの退避 /
      同じ run で WT と Claude Code の `settings.json` が両方退避される経路)
- [ ] self-check(OK/NG per completion criterion, record in checks/4.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)
- [ ] Design expert review (subagent)

**Completion criteria**:

- mac 上で `./setup.sh` が exit 0 で終わり、`~/.claude/settings.json` と
  `~/.claude/scripts/statusline.sh` が repo の原本と `diff` で一致する。2回流してもバイト列が
  変わらない
- 既存の管理対象(herdr / iTerm2)の配置先と冪等性が変わっていない
- WT と Claude Code の `settings.json` が同じ run で退避される状況で、2つの退避先が別の path になり、
  path だけでどちらのものか分かる
- 配置失敗時の挙動が変わっていない: 警告 → 残りを続行 → 末尾で列挙 → 非0で終了。
  `set -u` 致命 / SIGINT / SIGTERM / 意図的な `exit 1` の終了コードが従来どおり
- `claude` コマンドや `~/.claude` が存在しないマシンでも配置は成功し、run が落ちない

### #5: setup.sh にプラグインの導入を足す

**Purpose**: `settings.json` の宣言だけでは入らないプラグインの実体を、`setup.sh` が
`claude plugin marketplace add` / `claude plugin install` で導入するようにする。

**Prerequisites**: #4

**Steps**:

- [ ] 導入するプラグインと marketplace の指定元(`settings.json` から読むか、`setup.sh` に書くか)を
      #1 の設計どおりに実装する
- [ ] 隔離した `$HOME` で実測する(未導入マシンでの初回導入 / 導入済みマシンでの再実行 /
      `claude` コマンドが無いマシン / 導入コマンドが失敗したマシン)
- [ ] self-check(OK/NG per completion criterion, record in checks/5.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- 隔離した `$HOME`(プラグイン未導入)で `./setup.sh` を流したあと、`claude plugin list` が
  `settings.json` の `enabledPlugins` にあるプラグインを enabled として列挙する
- 導入済みのマシンで再実行しても run は exit 0 で終わり、二重導入やエラーにならない
- `claude` コマンドが無いマシンで run が失敗にならない(#1 で決めた通知の形になっている)
- 導入コマンドが失敗したときの扱いが #1 の設計どおりで、run の終了コードがそれと一致する
- 配置(`deploy`)の保証が変わっていない — プラグイン導入の成否が管理対象ファイルの配置結果に
  影響しない

### #6: README を更新する

**Purpose**: Claude Code の設定が管理対象に入ったことを、README の基準(再現に要るものだけ)で追記する。

**Prerequisites**: #5

**Steps**:

- [ ] 「設定対象」の表に Claude Code の行を足す
- [ ] 「直す前に」に、素直に読むと欠陥に見えるが意図している点があれば足す
- [ ] `setup.sh` が実行できず人がやるしかない手順があれば足す
- [ ] self-check(OK/NG per completion criterion, record in checks/6.md)
- [ ] Craft expert review (subagent, per the task's medium)

**Completion criteria**:

- README から、Claude Code のどの設定をどのファイルが持つかが読み取れる
- README に具体的な設定値(モデル名・テーマ名・プラグイン名・statusline の表示内容)が
  書かれていない
- `setup.sh` が実行時に表示する内容(配置先・退避・失敗時の扱い)が README に重複していない
- README と `setup.sh` と `steering.md` / `design.md` が矛盾しない

### #7: Evaluation sign-off

**Purpose**: Acceptance criteria を実行した結果をユーザーに提示し、セッションの完了判定を受ける。

**Prerequisites**: #6

**Steps**:

- [ ] Acceptance criteria を1つずつ実行し、結果をユーザーに提示する
- [ ] `/rn:ty`(承認)または `/rn:gm`(修正 → 指摘に対応して再提示)で判定を受ける

**Completion criteria**:

- Acceptance criteria の実行結果が承認されている

# State

(written by /rn:dn, read and reset to this placeholder by /rn:up. `Status` is `paused` while a
session is suspended — the signal /rn:up and /rn:dn search for — and resets to `not suspended` here,
so only a genuinely suspended session reads `paused`.)

- **Status**: not suspended
- **Date**: YYYY-MM-DD
- **Last completed**: #N description
- **Next**: #N description
- **Notes**: bounded forward pointer — branch/PR, next concrete action, open blockers, user-deferred paths, open questions / pending decisions not yet captured in `design.md`; not a re-narration of the session (that lives in `git log`)
