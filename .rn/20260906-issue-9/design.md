# Claude Code user settings reproduction — design notes

Not read at runtime — for whoever maintains the design and needs to judge whether a decision is still
right when requirements change.

## 1. Background & Goals

### 1.1 What is the goal?

herdr / iTerm2 / Windows Terminal と同じように、`~/.claude/settings.json` と、そこから使われる
`statusline.sh` を dotfiles の管理対象にする(Issue #9)。

### 1.2 What goes wrong without this?

新しいマシンでは Claude Code の設定を毎回手で作ることになる。加えて `enabledPlugins` /
`extraKnownMarketplaces` は宣言であって実体ではなく、宣言をコピーするだけではプラグインが使えない
(隔離 `$HOME` で実測済み、Issue #9 のコメント)。

### 1.3 What does reaching it require?

settings.json の各キーを repo が持つか判定し(§4.1)、既存の `deploy()` でコピーする。加えて、
このリポジトリが使う marketplace/plugin を、setup.sh に書いた明示的なコマンドで実体化する処理を
足す(§4.2)。当初は「宣言(settings.json)を読んで実体化する」形だったが、レビューで指摘された
とおり `enabledPlugins`/`extraKnownMarketplaces` は Claude Code 自身が書き戻すランタイムの状態で
あって設定ではないため、settings.json からは削り、setup.sh 側に直接書く形に変更した(§5.1)。

### 1.4 What is out of scope?

CLAUDE.md・出力スタイルの中身(Issue #10)。資格情報(settings.json に該当キーが無いことを確認済み)。
宣言から消えたプラグインのアンインストール(発生頻度が低く、手動の `claude plugin uninstall` で足りる
— steering.md Rules「レビューは目的に錨を下ろす」)。非公開 marketplace(公開 marketplace 以外は
未検証)。

## 2. Assumptions & Constraints

### 2.1 What do we take as true?

両OSとも settings.json の置き場所は同じで OS 分岐は不要(WSL 実機は未検証、根拠は既存 statusline.sh
の前提コメントのみ)。Claude Code 自身が settings.json を書き戻すが、「dotfiles が正」という既存の
関係(herdr/WT と同じ)がそのまま成り立つ。`claude plugin marketplace add` / `install` は公開
marketplace にログイン不要で通ることを実測済み(Issue #9 コメント)だが、**再実行時に冪等かどうかは
未測定** — §4.2 の事前チェック方式はこれに依存しない作りにする。`permissions.additionalDirectories`
での `~` 展開が効くかも未検証(実装タスクで確認)。

### 2.2 What binds the solution?

配置方式を増やさない(既存 Rules)。既存の `deploy()`(丸ごと上書き)にそのまま乗せる —
キー単位の差分更新はしない。

## 3. Design overview

### 3.1 What is the core idea, and why does it solve the problem?

「ファイルを置く」ことと「宣言を実体化する」ことを、はっきり別の処理として直列に並べる。ファイル
配置は既存の `deploy()` に乗せるだけで新しい保証を作らず、宣言の実体化だけを新しい小さな処理として
足す。

### 3.2 What are the pieces, and what is each responsible for?

- `claude/settings.json`(新規、repo) — `$HOME/.claude/settings.json` の原本。marketplace/plugin の
  宣言は持たない(ランタイムの状態であって設定ではないため — §5.1)
- `claude/scripts/statusline.sh`(新規、repo) — `settings.json` の `statusLine` が指す実体
- setup.sh への追加処理 — このリポジトリが使う marketplace/plugin を名指しした宣言そのものであり、
  同時にそれをコマンドで実体化する処理でもある(settings.json を読まない)

### 3.3 How does work move?

1. `claude/settings.json` を `deploy()` で配置する
2. `claude/scripts/statusline.sh` を `deploy()` で配置する(1と独立)
3. 既存の OS 別処理(iTerm2/WT)はそのまま
4. `herdr integration install claude` を事前チェック付きで実行する(§4.1)。既存の OS 分岐より
   後ろに置き、この処理の失敗が既存の再現(iTerm2/WT)を巻き込まないようにする。
5. setup.sh にハードコードした marketplace(`ccpm`)・plugin(`rn@ccpm`)を、`claude plugin
   marketplace add` / `claude plugin install` で事前チェック付きで実行する(§4.2)。4と同じ理由で
   OS 分岐より後ろに置く。

## 4. Detailed design

### 4.1 What does the settings.json/statusline.sh placement guarantee, and how is a breach caught?

**保証**: 既存の `deploy()` と同じ — exit 0 の run では repo の原本とバイト一致、2回流しても結果
不変、repo から消せばマシンからも消える。新しい保証は作らない。

**キーの仕分け**(確認時点で13キー、Claude Code 自身の書き戻しで今後変わりうる): 秘密・マシン
固有値は無し(確認済み)、すべて repo が持つ。うち2点だけ理由が要る:

- `hooks.SessionStart` は settings.json に持たない。`herdr integration install claude` が
  `~/.claude/hooks/herdr-agent-state.sh` を配置するのと同時に、このキー自体を生きている
  settings.json へ書き込むことを隔離 `$HOME` で実測済み(空の `$HOME` に repo の settings.json を
  置いた状態で実行 → `hooks.SessionStart` が追加され、2回目の実行は再現性がある = 冪等)。
  repo 側に書くと herdr が書き戻す値と二重の情報源になる点は §4.2 の
  `enabledPlugins`/`extraKnownMarketplaces` と同じ理由。setup.sh は §4.2 のプラグインと同じ
  precheck-then-invoke 形で、`herdr integration status` の出力(`claude: current` かどうか)を見て
  から `herdr integration install claude` を呼ぶ(既存の OS 分岐より後ろ、§3.3 の4)。`herdr` が
  無ければ `warn`(`record_failure` にはしない — settings.json 自体は正しく配置されているため)。
- `permissions.additionalDirectories`(`~/.claude/plugins/cache` 固定)— これが無いと §4.2 で
  実体化したプラグインの参照ファイル読み込みで毎回許可確認が出る

**破れの検出**: 白紙の `$HOME` から1回流し、配置先と repo を diff で確認する。継続的な検出は既存の
`deploy()` の冪等性チェック(2回目が `Up to date` を返すこと)に乗る。

### 4.2 What does the plugin realization step guarantee, and how is a breach caught?

**保証**: このリポジトリが使う marketplace(`ccpm` → `lovaizu/ccpm`)・plugin(`rn@ccpm`)を、
setup.sh にハードコードしたコマンドで使える状態にする。宣言(何を入れるか)と実体化(どう入れるか)
は同じ setup.sh の中にあるが、読むものは何もない — settings.json はもう見ない。実体はマシン側に
委ねる(コマンドを再実行すれば同じ実体が再現できるため)。

**3つの環境での終わり方**:

| 環境 | 結果 |
|---|---|
| `claude` / `jq` が無い | `warn`、run 全体は失敗にしない |
| すでに入っている(事前チェックで判定) | 何もしない(echo で FYI) |
| 入れようとして失敗した | `record_failure`、run 全体を非0で終える |

事前に現在の状態を確認してから実行する(precheck-then-invoke)ことで、コマンド自体が2回目の呼び出し
に冪等かどうかを知らなくてもこの3分類が成立する(2.1)。precheck は `claude plugin marketplace list
--json` / `claude plugin list --json` を読み、marketplace は `name`、plugin は `id` と
`enabled == true` で照合する(task #5 で実測、確定)。

**破れの検出**: 隔離 `$HOME` で上記3パターン(コマンド無し/未導入/導入済み/失敗)を実測した
(task #5)。

### 4.3 What does the backup-namespace change guarantee, and how is a breach caught?

`claude/settings.json` と `windows-terminal/settings.json` は配置先の basename が同じ
(`settings.json`)。既存のバックアップ命名(basename だけがキー)のままだと、同じ run で両方
バックアップされたときにどちらのものか区別できない(Acceptance criteria が名指しする「取り出す
ときにそれがどの設定のものか判別できる」に反する)。

**決定**: バックアップの命名キーを、配置先の basename から repo 内の相対パスに変える。全管理対象に
一律適用する — 2ファイルだけ変えると「配置方式を増やさない」Rules への部分的な例外になる。

**破れの検出**: 両方の settings.json が既存する隔離環境で1回流し、`$BACKUP_DIR` にそれぞれ別の場所
でバックアップが作られることを確認する。

## 5. Alternatives considered

### 5.1 Why this shape, and not another?

キー単位の差分マージは採らない(配置方式を増やさない Rules に反する)。

marketplace/plugin をどこに書くかは、当初「settings.json に宣言し、setup.sh がそれを読んで実体化
する」形にしていた。理由は「プラグイン一覧を setup.sh 側に別途書くと、settings.json と二重の情報源
になり、片方だけ更新して食い違う余地が生まれる」というものだった。

これはレビュー(PR #11)で誤りだと指摘された。`enabledPlugins`/`extraKnownMarketplaces` は
Claude Code 自身が `claude plugin install` の実行後に書き戻す値であり、そもそも「repo が持つ設定」
ではない — 実行してみないと正しい値が定まらないランタイムの記録であって、static な設定ファイルの
一部として repo 管理下に置くものではない。書き戻しの結果を repo にコピーして持ち帰る運用は静的な
設定と動的な状態を同じファイルに混ぜることになり、それ自体が二重の情報源だった。

そのため settings.json から `enabledPlugins`/`extraKnownMarketplaces` を削り、marketplace/plugin の
名指し(何を入れるか)は setup.sh 側にのみハードコードした。情報源は setup.sh 一箇所になり、
当初懸念していた「settings.json と setup.sh の食い違い」はそもそも起こり得ない(settings.json は
marketplace/plugin を宣言しなくなったため)。

### 5.2 What did we trade away?

`$BACKUP_DIR` は flat な1階層でなくなり、repo の構造を映した木構造になる(年数回しか流さない
利用状況では実害無しと判断)。プラグインが実際に「使える」ことの検証はコマンドの終了コードまでで、
それ以上(実際に有効化されて動くか)は確認しない。
