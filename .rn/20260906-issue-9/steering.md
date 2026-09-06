Rn version: 0.8.0
Design: .rn/20260906-issue-9/design.md

# Goal

この dotfiles が端末環境に対してやっていること — 「clone して `./setup.sh` を実行すれば、Win
(WSL + Windows Terminal)と Mac(iTerm2)で同じ状態になる」— を、その端末の中で毎日使う
Claude Code のユーザー設定にも広げる(Issue #9)。いまは端末だけが両OSで揃い、その中で動くものは
マシンごとに手で設定し直している。

対象は Claude Code の**ユーザー設定**。設定の宣言を repo に置くだけでは足りない — プラグインは
宣言と実体が別で、宣言を配っても実体は入らない(Issue #9 のコメントで隔離 `$HOME` において実測
済み)。**「設定を書いたファイルが置かれた」ではなく「Claude Code がその設定で動く」ところまで**を
`./setup.sh` の仕事にする。

**Claude Code の指示書(`CLAUDE.md` / 出力スタイル)は対象外** — Issue #10 として別に立っている。
端末環境そのもの(herdr / iTerm2 / Windows Terminal)の設定内容にも手を入れない。

# Acceptance criteria

- **新しいマシンで再現できる**。clone して `./setup.sh` を実行したあと、そのマシンの Claude Code が
  いまのマシンと同じ設定で動く — 使うモデル、statusLine の表示、出力スタイル、テーマ、そして
  repo が宣言したプラグインが有効なものとして使える状態。これが Win / Mac のどちらでも成り立つ
- **手で設定する手順が残らない**。残るものがあるなら、それは `./setup.sh` に原理的にできないこと
  (資格情報の入力など)に限られ、README がそれを手順として書いている
- **dotfiles が正**。Claude Code 自身がマシン側で書き換えた設定は、次の `./setup.sh` で repo の
  状態に戻る。repo から消した設定はマシンからも消える。同じ repo で2回流しても結果は変わらない
- **上書きされる前の設定が失われない**。`./setup.sh` が置き換えたものは後から取り出せ、取り出す
  ときにそれがどの設定のものか判別できる(Claude Code の設定と Windows Terminal の設定が同じ run で
  置き換えられる状況を含む)
- **run の終わり方が再現できたかどうかを言い切る**。全部反映できた run と、反映できなかったものが
  ある run が区別でき、後者は何が反映されなかったかを名指しする
- **repo に持ち込まないものがある**。資格情報・トークン・そのマシンでしか意味を持たない値が
  repo に入らない
- **dotfiles が原本を持たない設定を壊さない**。Claude Code の設定のうち他のプログラムが所有して
  いるものがあれば、`./setup.sh` はそれを上書きしない。それが無いマシンでも Claude Code が
  壊れた状態にならず、必要なものがあるなら読み手にそれが分かる
- **既存の再現が損なわれない**。herdr / iTerm2 / Windows Terminal の設定について、`./setup.sh` の
  結果(配置先・冪等性・失敗時と異常終了時の終わり方)が従来と変わらない
- README が**再現に要るものだけ**を追記している — (a) 設定対象(何をどのファイルが持つか)、
  (b) 設定ファイルを素直に読むと欠陥に見えるが意図している点、(c) `setup.sh` が実行できず人が
  やるしかない手順。**具体的な設定値は書かない**(モデル名・テーマ名・プラグイン名・statusline の
  表示内容はすべて設定ファイル側にしか置かない)。`setup.sh` が実行時に表示する内容も置かない
- **判断の理由が残っている**。`design.md` を読めば、要件が変わったときにその判断がまだ正しいかを
  第三者が判断できる
- `steering.md` / `design.md` / `setup.sh` / README が同じことを言っている

# Assumptions

- **Claude Code は両OSとも WSL / macOS 側の shell で動く**。Win では herdr が WT の WSL プロファイル
  の中で動き、その中で Claude Code が起動するので、設定の置き場所に OS 別の分岐は要らない。
  **WSL 実機では未検証の仮定**(いまの statusline スクリプト冒頭のコメントが「macOS /bin/sh と
  WSL の dash の両方で動く」と書いていることが傍証)
- Claude Code は自分のユーザー設定を書き戻す — 対話中にファイルの mtime が更新されることを実測。
  herdr の `config.toml` や WT の `settings.json` と同じ「アプリも書くが dotfiles が正」の関係になる
- プラグインの実体の導入は、公開 marketplace であればログイン不要 — 隔離 `$HOME` で
  `claude plugin marketplace add lovaizu/ccpm` → `claude plugin install rn@ccpm` が通ることを
  Issue #9 のコメントで実測済み。**非公開 marketplace はこの前提の外**
- いまの `outputStyle` / `theme` の値(`Concise` / `light`)は Claude Code 組み込みのもので、
  `~/.claude/output-styles/` や `~/.claude/themes/` にあるファイルには依存しない — よって
  それらは今回の対象に入らない(カスタム出力スタイルは Issue #10 側の話)
- statusline スクリプトは `sh <path>` として起動されるので、配置先に実行ビットは要らない。
  `cp` が新規作成先に元のモードを写すことも実測済み
- **マシンは mac 1台と Windows 1台**。既存の設定と同じく、丸ごと上書きが成り立つのはこの前提の下だけ

# Rules

- commit and push every change; one completion marker per task
- 会話・ドキュメントは日本語(コード・コミットメッセージは英語)
- **レビューは目的に錨を下ろす**。この dotfiles は1人用で、mac 1台と Windows 1台、`setup.sh` は
  対話的に年数回流すだけ、配置が失敗すれば端末を触った瞬間に分かる。レビューを回すときは依頼文に
  この利用状況を書き、「完了基準に照らして効かない指摘は挙げるな」を明示する。回す軸の数と周回数も
  ここから決める — 毎回フルセットにしない
- 端末環境そのものの設定(`herdr/config.toml` / `iterm2/herdr.json` /
  `windows-terminal/settings.json`)の**中身には手を入れない**
- **配置方式を増やさない**。既存の管理対象はすべて1つの方式(丸ごと上書き)で配られており、
  ファイルごとの例外を持たない — Claude Code の設定のためにこの原則を崩さない(design.md §4.6)
- `setup.sh` の既存の機構(終端番兵 `REACHED_END`、`HOME` の入口ガード、XDG 値の絶対パス検査、
  `deploy` が常に 0 を返す規約、大文字/小文字の命名規則)を壊さない — いずれも
  design.md §4.6 が exit 0 の意味を支えるために置いたもの
- このファイルと `design.md`、`checks/` は**常に最新状態に保つ**。変更履歴・撤回した内容の手順・
  実施済みレビューのチェックボックスは残さない — それらは git log と成果物から辿れる。
  残すのは「なぜそうしたか」と、決定に紐づくレビュー指摘・対応要否・対応内容

# Tasks

### #1: 設計を決めて design.md に書く

**Purpose**: Claude Code のユーザー設定を再現するための判断 — 何を repo が持ち何を持たないか、
置き換えたものをどう判別可能にするか、宣言と実体が別なものをどう扱うか — を決め、その理由が
後から辿れる形で `.rn/20260906-issue-9/design.md` に残す。

**Prerequisites**: none

**Steps**:

- [ ] Claude Code のユーザー設定を「repo が持つもの / マシン側に委ねるもの / 他のプログラムが
      所有するもの / 秘密」に仕分ける
- [ ] 置き換えたものが後から判別できる形を決める(Claude Code と Windows Terminal の設定が
      同じ run で置き換えられる状況を含む)
- [ ] 宣言と実体が別のもの(プラグイン)の扱いを決める — 実体を入れられない環境・すでに入って
      いる環境・入れようとして失敗した環境で run がどう終わるか
- [ ] design-template.md の5節すべてに decision + reasoning で答える
- [ ] self-check(OK/NG per completion criterion, record in checks/1.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)
- [ ] Design expert review (subagent)

**Completion criteria**:

- `design.md` を読んだ第三者が、Acceptance criteria の各状態をこの設計がどう満たすかを辿れ、
  その判断が要件の変化に対してまだ正しいかを判断できる。h3 の問いに未回答のものが無い
- repo が持たないと決めた設定について、持たない理由が書かれている
- 置き換えたものの判別可能性について、それをどう保証するかと、既存の再現(herdr / iTerm2 /
  Windows Terminal)に及ぶ影響が書かれている
- 宣言と実体が別のものについて、実体を入れられない環境・すでに入っている環境・入れようとして
  失敗した環境の3つで run がどう終わるかがそれぞれ決まっている
- 決めていないことを決めたように書いていない — 未検証の仮定は仮定として名指しされている

### #2: Design sign-off

**Purpose**: `design.md` の設計をユーザーに提示し、実装に入る前に承認を取る。

**Prerequisites**: #1

**Steps**:

- [ ] `design.md` をユーザーに提示する
- [ ] `/rn:ty`(承認)または `/rn:gm`(修正 → 指摘に対応して再提示)で判定を受ける

**Completion criteria**:

- `design.md` が承認されている

### #3: Claude Code の設定を repo の原本にする

**Purpose**: いまのマシンの Claude Code のユーザー設定を、#1 の仕分けに従って repo が持つ原本に
する。以降、repo が「その設定はこうである」と言える状態にする。

**Prerequisites**: #2

**Steps**:

- [ ] repo が持つと決めた設定を repo に置く
- [ ] 秘密とマシン固有の値が入っていないことを確認する
- [ ] 原本だけを与えた環境で Claude Code が起動し、いまのマシンと同じ設定で動くことを確認する
- [ ] self-check(OK/NG per completion criterion, record in checks/3.md)

**Completion criteria**:

- repo の原本だけを与えた `$HOME` で Claude Code が起動し、いまのマシンと同じ設定で動く —
  使うモデル、statusLine の表示、出力スタイル、テーマが一致し、設定エラーが出ない
- repo の原本に資格情報・トークン・そのマシンでしか意味を持たない値が含まれていない
- repo が持たないと決めた設定が原本に混ざっていない

### #4: `./setup.sh` が Claude Code の設定を再現するようにする

**Purpose**: `./setup.sh` を実行するだけで、そのマシンの Claude Code の設定が repo の原本と同じ
状態になり、以後 repo が正であり続けるようにする。

**Prerequisites**: #3

**Steps**:

- [ ] Claude Code の設定を再現する処理を `setup.sh` に足す
- [ ] 置き換えたものが後から判別できる形を #1 の設計どおりに実装する
- [ ] 隔離した `$HOME` で実測する(何も無い環境 / 再実行 / マシン側で書き換えたあと /
      Claude Code と Windows Terminal の設定が同じ run で置き換えられる経路 /
      他のプログラムが所有する設定が無い環境 / 再現に失敗する経路)
- [ ] self-check(OK/NG per completion criterion, record in checks/4.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)
- [ ] Design expert review (subagent)

**Completion criteria**:

- Claude Code の設定が何も無い `$HOME` で `./setup.sh` を流すと、Claude Code が repo の原本と同じ
  設定で動く状態になる。続けてもう一度流しても結果は変わらない
- マシン側で設定を書き換えたあとに `./setup.sh` を流すと、repo の状態に戻る。repo から設定を
  消して流すと、マシンからも消える
- `./setup.sh` が置き換えたものは後から取り出せ、取り出すときにそれがどの設定のものか判別できる。
  Claude Code と Windows Terminal の設定が同じ run で置き換えられても混同しない
- 再現できなかったものがある run は、何ができなかったかを名指しし、全部できた run と区別できる
  形で終わる
- Claude Code の設定のうち他のプログラムが所有しているものを `./setup.sh` が上書きしない。
  それが無いマシンでも run は残りの再現を完了し、Claude Code が壊れた状態にならない
- herdr / iTerm2 / Windows Terminal の再現結果が変わっていない — 配置先・冪等性・失敗時と
  異常終了時(`set -u` 致命 / SIGINT / SIGTERM / 意図的な非0終了)の終わり方が従来どおり

### #5: 宣言だけでは入らないもの(プラグイン)まで再現する

**Purpose**: repo がプラグインを宣言しているだけの状態から、そのプラグインが実際に使える状態まで
`./setup.sh` が持っていくようにする。

**Prerequisites**: #4

**Steps**:

- [ ] プラグインの実体を用意する処理を `setup.sh` に足す
- [ ] 隔離した `$HOME` で実測する(実体が無い環境 / すでに入っている環境 / 用意できない環境 /
      用意に失敗する環境)
- [ ] self-check(OK/NG per completion criterion, record in checks/5.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- プラグインが何も入っていない `$HOME` で `./setup.sh` を流したあと、repo が宣言したプラグインが
  有効なものとして使える
- すでに入っている環境で流しても、使える状態と run の終わり方が変わらない
- プラグインの実体を用意できない環境でも、設定そのものの再現は完了する。プラグインまで再現できた
  かどうかは run の終わり方から読み取れる
- #4 で満たした状態が壊れていない — 設定の再現結果と run の終わり方が、プラグイン側の成否に
  引きずられない

### #6: README を更新する

**Purpose**: Claude Code の設定が再現対象に入ったことを、README の基準(再現に要るものだけ)で
追記し、repo 全体が同じことを言っている状態にする。

**Prerequisites**: #5

**Steps**:

- [ ] 「設定対象」に Claude Code の行を足す
- [ ] 素直に読むと欠陥に見えるが意図している点があれば「直す前に」に足す
- [ ] `setup.sh` が実行できず人がやるしかない手順があれば足す
- [ ] self-check(OK/NG per completion criterion, record in checks/6.md)
- [ ] Craft expert review (subagent, per the task's medium)

**Completion criteria**:

- README から、Claude Code のどの設定をどのファイルが持つかが読み取れる
- 新しいマシンで人がやるしかない手順が残っているなら README にあり、残っていないなら書かれていない
- README に具体的な設定値(モデル名・テーマ名・プラグイン名・statusline の表示内容)が
  書かれていない。`setup.sh` が実行時に表示する内容も重複していない
- README / `setup.sh` / `steering.md` / `design.md` が同じことを言っている

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
