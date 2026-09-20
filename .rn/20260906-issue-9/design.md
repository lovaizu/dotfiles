# Claude Code user settings reproduction — design notes

Not read at runtime — for whoever maintains the design and needs to judge whether a decision is still
right when requirements change.

## 1. Background & Goals

### 1.1 What is the goal?

herdr / iTerm2 / Windows Terminal と同じ「dotfiles が正、`./setup.sh` で両OSが揃う」状態を、毎日使う
Claude Code の**ユーザー設定**(`~/.claude/settings.json` と、そこから参照される
`scripts/statusline.sh`)にも広げる(Issue #9)。範囲の基準は「Claude Code がその設定で動くところまで
を `setup.sh` の仕事にする」(steering.md Goal)であり、「ファイルが `~/.claude/` の下に存在する」
ではない。この違いが、プラグインを宣言だけでなく実体まで用意する、という4.4の決定を生む。

### 1.2 What goes wrong without this?

新しいマシンでは毎回手作業になり、他の対象で解決済みの「マシンごとに揃わない」問題がここだけ残る。
さらに `enabledPlugins` / `extraKnownMarketplaces` は**宣言であって実体ではない** —
隔離した `$HOME` に `settings.json` だけを置いても `claude plugin list` は "No plugins installed" を
返す(Issue #9 で実測)。宣言をコピーするだけでは「プラグインが使える」という実感を満たさない。

### 1.3 What does reaching it require?

- `settings.json` の各キーを「repo が持つ/マシン側に委ねる/秘密」に仕分け(§4.1)、参照先ファイルは
  「他のプログラムが所有するか」で別に仕分ける(`herdr-agent-state.sh` は所有外、§4.3)。
- 仕分けた原本を既存の `deploy()`(丸ごと上書き)にそのまま乗せ、新しい配置方式を作らない。
- `windows-terminal/settings.json` と `claude-code/settings.json` の basename 衝突によるバックアップ
  命名の解消(§4.2)。
- `enabledPlugins` / `extraKnownMarketplaces` の宣言を、コマンド呼び出しで実体化する経路を
  `deploy()` の外に追加する(§4.4)。

### 1.4 What is out of scope?

- **CLAUDE.md・出力スタイル/テーマの中身**。Issue #10 に切り出し済み(steering.md Goal)。値としての
  `outputStyle`/`theme`(組み込み名)は対象だが、カスタム定義ファイルは対象外。
- **資格情報・トークン**。実物のキーに該当なし。将来増えたら `settings.local.json`(このリポジトリは
  管理しない)に逃がす、という判断だけを残す。
- **`settings.json` 以外の Claude Code の状態**。steering.md の Goal が対象を settings.json に絞る。
- **herdr / iTerm2 / Claude Code 本体・`jq` のインストール**。この dotfiles は「入っていることを前提に
  設定を揃える」ものであり、アプリ本体は配らない(herdr4mac design.md と同じ理由)。
- **非公開 plugin marketplace**。実測できているのは公開 marketplace のみ(steering.md Assumptions)。
- **`herdr-agent-state.sh` の中身**。herdr が所有するファイルであり、中身には触れない(§4.3)。
- **宣言から消えたプラグイン/marketplace のアンインストール・登録解除**。§4.4 が作るのは追加方向
  (add/install)のみ。理由: (1) 利用頻度が低く手動対応で足りる、(2) 残存の実害は「不要な配置が残る」
  程度、(3) 追加/削除を対称に作ると severity 分類を二重に持つことになり複雑さに見合わない
  (steering.md Rules「レビューは目的に錨を下ろす」)。ただし機能面は正直に書く: `enabledPlugins` の
  宣言を消しても、Claude Code は `defaultEnabled`(既定 `true`)にフォールバックするだけなので
  **プラグインが無効化される保証はない** — 明確に無効化したいなら利用者が
  `claude plugin disable` を別途実行する必要がある。

## 2. Assumptions & Constraints

### 2.1 What do we take as true?

- Claude Code は両OSとも WSL/macOS の shell で動くため OS 別分岐は不要(steering.md Assumptions)。
  **WSL 実機では未検証**(statusline スクリプトの前提コメントのみが根拠)。
- Claude Code は自分の `settings.json` を書き戻す(実測済み)。herdr/WT と同じ「dotfiles が正」の
  関係になり、方式を分ける理由にならない。
- `claude plugin marketplace add` / `claude plugin install` が公開 marketplace にログイン不要で
  通ることは実測済み(Issue #9)。
- **上記2コマンドの再実行に対する冪等性は未測定**。§4.4 は事前チェックでこれを回避し、コマンド自体の
  冪等性に依存しない作りにする。
- **`claude plugin marketplace list` / `claude plugin list` の出力形式も未測定**(自然文の例以上の
  確認なし)。判定の要否と結果の扱い(severity)だけを本設計が決め、具体的な実装は task #5 に委ねる。
- `scripts/statusline.sh` は `sh <path>` で起動されるため実行ビット不要、`cp` が元のモードを写すことは
  実測済み。
- マシンは mac 1台・Windows 1台のみ。丸ごと上書きは「両マシンが同じ設定を志向する」前提の下でのみ
  成立する。
- **`permissions.additionalDirectories` での `~` 展開は未検証**。公式ドキュメントの例は相対パスのみで、
  他キーでの `~` 展開実例があってもこのキーで効くかは確認できていない。task #3/#4 が隔離環境で実測
  して確定させる。効かない場合、絶対パスはマシン固有値になり repo が持てなくなるため、このキー自体を
  設計から外す判断になる。
- **`herdr-agent-state.sh` 不在時に Claude Code 自体が壊れないかは未検証**。steering.md Acceptance
  criteria「壊れた状態にならず」に対応し、task #4 の隔離環境での実測が確定させる。

### 2.2 What binds the solution?

- **配置方式を増やさない**(steering.md Rules)。管理対象はすべて既存の `deploy()` に乗せ、キー単位の
  差分更新のような例外は作らない。
- **`deploy()` は「読んで一部を書き換える」ことができない**(cmp -s + 丸ごと rename)。repo 側
  `settings.json` は持たせたいキーの全体を過不足なく表現する必要があり、これがマシン固有値・秘密を
  混ぜられない理由になる。
- 既存の機構(`REACHED_END`、`HOME` の入口ガード、XDG 絶対パス検査、`deploy` が常に0を返す規約)は
  壊さない。本設計が追加する機構(§4.2〜§4.4)はこの上に積む。
- `jq` はこのマシンにすでに存在する前提(`statusline.sh` が実行時に使用)。§4.4 で `setup.sh` 自身が
  `jq` を要求するのは新しいが、`jq` というツール自体を新規に要求するわけではない。
- `settings.json` / `scripts/statusline.sh` は XDG のような可変 base directory を持たない
  (`~/.claude/` 固定という観測に基づく前提)。

## 3. Design overview

### 3.1 What is the core idea, and why does it solve the problem?

Claude Code の設定を既存の `deploy()` に乗せつつ、**ファイルの配置**と**宣言の実体化**を別の機構として
直列に並べる。

- ファイル配置(`settings.json`、`scripts/statusline.sh`)は herdr/iTerm2/WT と同じ方式に乗る。
- 宣言の実体化(プラグインを実際に使える状態にする)はコマンド起動であり `deploy()` には乗せず、
  既存の severity 語彙(record_failure/warn/echo)を再利用する別の小さな機構にする。

これにより「宣言と実体は別」という Issue #9 の教訓を、ファイル配置側の既存の保証を崩さずに追加できる。

### 3.2 What are the pieces, and what is each responsible for?

- **`claude-code/settings.json`(新規)** — `$HOME/.claude/settings.json` の原本(§4.1)。
- **`claude-code/scripts/statusline.sh`(新規)** — `statusLine` が参照する実体(§4.1)。
- **`backup_path_for()` の改修** — バックアップの命名キーを basename から repo 内相対パスへ(§4.2)。
- **`herdr-agent-state.sh` の不在チェック(新規)** — 管理はせず、存在確認と `warn` のみ(§4.3)。
- **プラグイン実体化ステップ(新規)** — repo 側 `settings.json` を読み、`marketplace add` /
  `install` を事前チェック付きで呼ぶ(§4.4)。

### 3.3 How does work move?

`setup.sh` の中で、既存の herdr `config.toml` 配置の直後に、Claude Code 関連の処理を**OS 非分岐**で
追加する。後段が前段に依存する箇所だけ直列で、それ以外は独立に失敗しうる:

1. `claude-code/settings.json` を `deploy()` で配置。
2. `claude-code/scripts/statusline.sh` を `deploy()` で配置(1と独立)。
3. `herdr-agent-state.sh` の存在確認。無ければ `warn`(1の成否と独立)。
4. 既存の OS 分岐(iTerm2/フォント、または WT)に入る。
5. repo 側 `settings.json` を `jq` で読み、`extraKnownMarketplaces` の `marketplace add` をすべて
   終えてから `enabledPlugins` の `install` を呼ぶ(事前チェック付き。未測定の冪等性には依存しない)。
   **既存 OS 分岐より後ろに置く理由**: `setup.sh` は `set -e` の下で動き、既存の `deploy()`/`warn` は
   常に0を返すよう作られている。新規のコマンド呼び出しが同じ厳密さでガードし損ねた場合の巻き込みが、
   既存の再現(iTerm2/WT の配置)に及ぶ前にそちらを終わらせておく。
6. 最後に既存の `FAILURES` 集計へ合流する(同じ配列・同じ `REACHED_END` 判定)。

## 4. Detailed design

### 4.1 What does the claude-code/ file set guarantee, and how is a breach caught?

対象は2ファイル: `claude-code/settings.json` → `$HOME/.claude/settings.json`、
`claude-code/scripts/statusline.sh` → `$HOME/.claude/scripts/statusline.sh`。新しい配置方式を作らず
既存の `deploy()` に乗せる。

**保証**: herdr4mac design.md §4.6 の保証がそのまま及ぶ — exit 0 の run ではこの2ファイルは原本と
バイト単位で一致し、2回流しても結果は変わらず、repo から消せばマシンからも消え、Claude Code 自身の
書き戻しは次の run で repo の値に戻る。

**キーの仕分け(確認時点で13キー。Claude Code 自身の書き戻しで今後変わりうる観測値として扱う)**:

| キー | 分類 | 理由 |
|---|---|---|
| `model` | repo が持つ | Acceptance criteria が名指し。秘密性・マシン固有性なし |
| `hooks.SessionStart` | repo が持つ(JSON として) | ファイル丸ごと上書きのためスタンザ単位で所有者を分けられない。参照先スクリプトは対象外(§4.3) |
| `statusLine` | repo が持つ | 参照先 `scripts/statusline.sh` も合わせて新規管理対象にする |
| `enabledPlugins` / `extraKnownMarketplaces` | repo が持つ(宣言として) | 実体化は §4.4 |
| `outputStyle` / `theme` | repo が持つ(値のみ) | 組み込み名の指定で定義ファイルを伴わない(2.1)。カスタム値は対象外(Issue #10) |
| `effortLevel` / `tui` / `skipDangerousModePermissionPrompt` / `remoteControlAtStartup` / `agentPushNotifEnabled` | repo が持つ | 秘密性・マシン固有性が無く、丸ごと上書きである以上、個別に対象外としない限り repo 側に入る |
| `permissions.additionalDirectories` | repo が持つ(`~/.claude/plugins/cache` に固定) | worktree でのプラグイン開発時、参照ファイル読み込みのたびに許可確認が出る摩擦を消す。§4.4 の実体化と対になって初めて意味を持つ。範囲を `~/.claude/plugins` 全体に広げないのはユーザーとの合意。`~` 展開自体は未検証(2.1) |

**マシン側に委ねる設定**: 該当なし。2台が同じ設定を志向する前提の下でのみ丸ごと上書きが成立して
おり、意図的に変えたい値は今は無い。将来必要になったら `settings.local.json` に逃がす。

**秘密**: 該当なし(実物確認済み)。将来現れたら repo が持たない側に倒す原則だけを確認しておく。

**破れの検出**: 新しい clone から `./setup.sh` を1回流し `diff` で一致を確認。継続的な検出は既存の
`cmp -s` idempotency チェックに乗る。

### 4.2 What does the backup-namespace key change guarantee, and how is a breach caught?

**衝突の実体**: 既存の `backup_path_for()` は配置先の **basename** をキーにした flat namespace で、
「basename が互いに異なる」ことを規約として前提にしている。`claude-code/settings.json` と
`windows-terminal/settings.json` はどちらも basename `settings.json` — WSL の同じ run で両方
デプロイされる(2.1)ため衝突する。`backup_file()` の同一秒内重複回避があるのでデータは消えないが、
どちらのバックアップか**ファイル名から判別できない**。Acceptance criteria が名指しする「どの設定の
ものか判別できる」に反する。

**決定**: バックアップの命名キーを、配置先の basename ではなく**管理対象の repo 内相対パス**
(例: `claude-code/settings.json`)に変える。`$BACKUP_DIR` はこの相対パスをそのまま木構造として持つ
(例: `$BACKUP_DIR/claude-code/settings.json.<timestamp>.bak`)。全管理対象への一律適用とし、
2ファイルだけの部分的な例外にはしない。

理由:
1. **Rules「配置方式を増やさない」** — 部分適用は命名方式が2種類になり、それ自体が例外になる。
2. **basename 規約は実行時チェックではなく convention** — repo 内相対パスなら「同じ repo に同じ
   パスは存在し得ない」というファイルシステムの性質が一意性を保証し、人間による目視確認が要らなくなる。

具体的な引数変更(`backup_path_for()`/`backup_file()` のどちらにどう渡すか)は実装タスク(#3/#4)が
決める。既存バックアップは basename のまま `$BACKUP_DIR` 直下に残り、読み書き・削除の対象にしない
(移行は非破壊的)。この一律適用により herdr/iTerm2 のバックアップも同様にネストした置き場所に
変わるが、配置先・冪等性・失敗時の挙動(herdr4mac design.md §4.6 の保証)には影響しない。

**破れの検出**: WSL 相当の環境(`windows-terminal/settings.json` と `claude-code/settings.json`
双方に既存ファイルを置いた隔離 `$HOME`)で `./setup.sh` を1回流し、`$BACKUP_DIR/windows-terminal/`
と `$BACKUP_DIR/claude-code/` に1件ずつバックアップができ、互いを上書きしないことを確認する。

### 4.3 What does excluding herdr-agent-state.sh guarantee, and how is a breach caught?

`~/.claude/hooks/herdr-agent-state.sh` はヘッダーに "installed by herdr" / "managed by herdr" と
明記されている(確認済み)— herdr 自身の連携インストーラが所有・上書きするファイルで、このリポジトリが
原本を持つファイルではない。

**決定**: このファイルを管理対象にしない。repo にコピーを置かず `deploy()` を呼ばない。

**理由**: `deploy()` の丸ごと上書きは「1つの配置先に1つの書き手」を前提にする。repo でも管理すると、
herdr の再インストールのたびに herdr が上書きし、次の `setup.sh` で dotfiles が上書き返す、という
無言の取り合いになる。herdr4mac design.md §4.6 の「アプリも書くが dotfiles が正」とは違う構図 —
`herdr-agent-state.sh` は中身そのものが herdr のバージョンに紐づくロジック
(`HERDR_INTEGRATION_VERSION`)で、dotfiles 側が「正しい中身」を知る立場にない。

**このファイルが無い機械での挙動**: `settings.json` の `hooks.SessionStart` はこのパスを無条件に
参照する。herdr 連携が無い機械では配置直後にパスが存在しない状態になりうる。

**決定: `settings.json` 配置後に存在確認し、無ければ `warn`**(`record_failure` にはしない・黙らない)。
- `record_failure` にしない理由: 管理対象(`settings.json`)自体は正しく配置されており、
  herdr4mac design.md §4.6 の「管理対象が届かなかった」場合に該当しない。
- 黙らない理由: 放置するとフックの実行が毎セッション静かに失敗し続ける。iTerm2 の既定プロファイル
  警告(herdr4mac design.md §4.5)と同じ「配置は正しいが外部前提が満たされない」構図。
  **フック呼び出し失敗が Claude Code セッション自体を壊さないことは未検証の前提**(2.1、task #4
  が確定させる)。

両マシンとも herdr の Claude Code 連携を使う、というのが本設計の前提。崩れたら
(`hooks.SessionStart` を repo の `settings.json` から外すなど)別の判断が必要になるが、それは
そのときの design.md 改訂で扱う。

**破れの検出**: `herdr-agent-state.sh` を置かない隔離 `$HOME` で `./setup.sh` を1回流し、
`settings.json` は配置されつつ warn が出ることを確認。置いた状態では warn が出ないことも確認する。

### 4.4 What does the plugin realization step guarantee, and how is a breach caught?

`extraKnownMarketplaces` / `enabledPlugins` は**宣言**であり、`claude plugin marketplace add` /
`claude plugin install` という**コマンド呼び出し**だけが実体を作る(Issue #9 で確認)。実体
(`~/.claude/plugins/` 配下)自体は repo が持たず**マシン側に委ねる**(コマンドを再実行すれば再現
できるという意味)。宣言(`settings.json`)だけを単一の入力源にし、marketplace/plugin の一覧を
setup.sh 側に別途書かない(§5)。

**ファイル配置とは別の機構にする理由**: `deploy()` は「丸ごと置き換え、cmp -s で idempotent 性を
測る」ことに特化しており、コマンドの成功/失敗/冪等性はこの型に合わない。既存の severity 語彙
(`record_failure`/`warn`/素の `echo`)だけを再利用した別の小さな機構にする。

**severity の割り当て**:

| 状況 | severity | 理由 |
|---|---|---|
| `claude`/`jq` が無い | `warn`(run は非0にならない) | このリポジトリが配布・インストールするものではない(1.4)。Homebrew 無しでのフォント導入(herdr4mac design.md §4.5)と同じ「外部前提ツールが無い」カテゴリ |
| すでに入っている(precheck で判明) | 素の `echo` | 何も変える必要が無く、読み手に求めることも無い |
| `claude` はあるのに `add`/`install` が失敗 | `record_failure`(run は非0) | Acceptance criteria が「プラグインが有効に使える状態」をモデル名や statusLine と同格の再現条件に挙げている |

**未測定の冪等性への対処**: 「実行してみてエラー文言を判定する」方式は `add`/`install` のエラー文言・
終了コードの意味を知っている必要があり未測定。代わりに**先に状態を確認してから実行する**
(precheck-then-invoke、既存の brew idiom と同型)ことで、コマンド自体の冪等性を知らなくてもこの
3分類が成立する。precheck に使う具体的なコマンド・出力形式(`marketplace list`/`plugin list`)は
自然文の例以上に確認できておらず**未測定のまま残す** — steering.md task #5 が実測して確定させる。
本設計は判定の存在と返す先(severity)だけを決める。

**実行順序**: `extraKnownMarketplaces` 全エントリの `marketplace add` を終えてから `enabledPlugins`
の `true` エントリの `install` に入る(`plugin@marketplace` という表記が依存関係を表すため)。

**`enabledPlugins` の `false` エントリは対象外**(Acceptance criteria の「有効な」に対応)。現在は
`false` のエントリが無く、将来増えたら再検討する。

**破れの検出**: 隔離 `$HOME` で (a) `claude`/`jq` が無い、(b) 未導入、(c) 導入済み、
(d) `add`/`install` が失敗する(例: ネットワーク遮断)の4パターンを実測し(task #5)、それぞれが
上記のどの経路をたどり run がどの exit code で終わるかを確認する。

**宣言からの削除(アンインストール)は対象外** — 理由は1.4。

## 5. Alternatives considered

- **キー単位の差分マージ**は採らない。`deploy()` の cmp -s ベース idempotency を JSON マージに
  置き換える必要があり、「配置方式を増やさない」Rules に反する。
- **marketplace/plugin 一覧を setup.sh 側にハードコード**は採らない。`settings.json` と二重の情報源
  になり、片方だけ更新してズレる。
- **プラグイン実体化を `deploy()` に押し込む**のは採らない(§4.4)。コマンド呼び出しは
  `deploy()` の型に合わず、「常に0を返す」契約を曖昧にする。
- **バックアップ衝突を片方だけ命名変更で解消**は採らない。「配置方式を増やさない」Rules への部分的な
  例外になり、次の衝突のたびに同じ判断をやり直すことになる。
- **配置先の basename 自体を変える**のは採らない。アプリ側(Windows Terminal/Claude Code)が固定で
  期待する名前であり、dotfiles 側の都合で変えられない。

**トレードオフ**:
- `$BACKUP_DIR` は flat から repo 構造を映した木構造になる。手でのバックアップ探索は1階層では
  済まなくなるが、年数回しか流さない利用状況(steering.md Rules「レビューは目的に錨を下ろす」)では
  実害が無い。
- `setup.sh` は実行時に `jq` を新たに要求する(既存の統合依存であり新規ツールではない)。
- 非公開 marketplace・`false` 宣言プラグインの実体化は作り込まない。必要になった時点で design.md を
  改訂する。
- プラグインが「使える」ことの検証はコマンドの終了コードまでで、実際に有効化されて動くかは確認しない
  (iTerm2/フォント導入と同じ深さ)。
