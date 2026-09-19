# Claude Code user settings reproduction — design notes

Not read at runtime — for whoever maintains the design and needs to judge whether a decision is still
right when requirements change.

## 1. Background & Goals

### 1.1 What is the goal?

この dotfiles がすでに端末環境(herdr / iTerm2 / Windows Terminal)に対してやっていること —
clone して `./setup.sh` を実行すれば両OSで同じ状態になり、dotfiles が正で、機械側の書き換えは次の
run で巻き戻る — を、その端末の中で毎日使う Claude Code の**ユーザー設定**にも広げる(Issue #9)。
今はこの部分だけが「マシンごとに手で作る」状態で、herdr / iTerm2 / WT と扱いが揃っていない。

対象は具体的には `~/.claude/settings.json` と、そこから参照されていて repo が原本を持つべきファイル
(後述の `scripts/statusline.sh`)。範囲を決める基準は「Claude Code がその設定で動くところまでを
`setup.sh` の仕事にする」(steering.md Goal)であって、「設定を書いたファイルが `~/.claude/` の下に
存在する」ではない — この違いが、プラグインを宣言だけでなく実体まで用意する、という後述の決定を生む。

### 1.2 What goes wrong without this?

新しいマシン(あるいは初期化した `$HOME`)では Claude Code の設定を毎回手で作り直すことになり、
herdr / iTerm2 / WT では無くなったはずの「マシンごとに揃わなくなる」問題がここだけ残る。
さらに Issue #9 が突き止めた固有の落とし穴として、`enabledPlugins` / `extraKnownMarketplaces` は
**宣言**であって実体ではない — 隔離した `$HOME` に `settings.json` だけを置いても
`claude plugin list` は "No plugins installed" を返す(Issue #9 のコメントで実測)。宣言をコピー
するだけの再現は、「プラグインが有効なものとして使える」という利用者の実感を満たさないまま
「設定ファイルは揃っている」という見かけだけを作ってしまう。

### 1.3 What does reaching it require?

- `~/.claude/settings.json` の各キーを「repo が持つ/マシン側に委ねる/秘密」に仕分け、repo が
  持つと決めた内容だけを repo の原本にする(§4.1)。これとは別に、`settings.json` が**参照する
  ファイル**については「他のプログラムが所有するか」を仕分けの基準にする — `hooks.SessionStart`
  が指す `~/.claude/hooks/herdr-agent-state.sh` はこの基準で管理対象から外す(§4.3)。「repo が
  持つ/マシン側に委ねる/他のプログラムが所有する/秘密」という4区分自体は変えないが、キーの仕分け
  (§4.1)と参照先ファイルの除外判断(§4.3)は別の対象に対する別の仕分けであり、「他のプログラムが
  所有する」は settings.json のキーには一度も現れない(現物のキーにそのような値は無い)。
- その原本を、既存の `deploy()`(丸ごと上書き)にそのまま乗せる — Claude Code 用に新しい配置方式を
  作らない(Rules「配置方式を増やさない」)。`statusLine` が指す `scripts/statusline.sh` も同じ扱いの
  管理対象にする(§4.1)。
- `windows-terminal/settings.json` と `claude-code/settings.json` が同じ basename
  (`settings.json`)を持つために起きる、バックアップの命名衝突を解消する(§4.2)。
- `enabledPlugins` / `extraKnownMarketplaces` という宣言を、`claude plugin marketplace add` /
  `claude plugin install` という**コマンド呼び出し**によって実体化する経路を、`deploy()` の外に
  一段追加する(§4.4)。
- `~/.claude/hooks/herdr-agent-state.sh` のように**他のプログラム(herdr)が所有するファイル**を
  管理対象に含めない決定と、それが無い機械での挙動を決める(§4.3)。

### 1.4 What is out of scope?

- **Claude Code の指示書(`CLAUDE.md` / 出力スタイルの中身)**。steering.md の Goal が明示的に
  Issue #10 へ切り出している。`outputStyle` / `theme` という**設定値**(組み込み名の指定)は本設計の
  対象だが、`~/.claude/output-styles/` や `~/.claude/themes/` に**カスタム定義ファイルを置く**ことは
  対象外 — 現在の outputStyle/theme の値は Claude Code 組み込みのもので、そのファイル群に依存しない
  ことが steering.md の Assumptions で確認済み。
- **資格情報・トークン**。`~/.claude/settings.json` の実物にそのようなキーは無い(確認済み)。
  Claude Code の認証情報は別の仕組み(このマシンでは未調査だが、少なくとも `settings.json` の外)に
  あるという前提を置く。将来 `settings.json` に秘密性のあるキーが増えたら、このキーだけは repo の
  原本に**含めず**、Claude Code 自身が読む `settings.local.json`(このリポジトリは作らない・管理し
  ない)に逃がすという判断を都度下す必要がある — 今回はその判断を要するキーが無いので実装しない。
- **`~/.claude/settings.json` 以外の Claude Code の状態**(例えばプロジェクトごとの信頼設定や会話
  履歴を持つとおぼしき他の状態ファイル)。steering.md の Goal が対象を「ユーザー設定」
  (`settings.json`)に絞っており、本セッションではそれ以外のファイルの中身を確認していない。
- **herdr / iTerm2 / Claude Code 本体・`jq` のインストール**。既存の `1.4`(herdr4mac design.md)が
  herdr 本体・iTerm2 のインストールを対象外としているのと同じ理由 — この dotfiles は「入っている
  ことを前提に設定を揃える」ものであって、アプリ本体の配布はしない。`claude` コマンドや `jq` が
  無い機械での扱いは §4.4 で決めるが、「無ければ入れる」処理は作らない(brew 経由のフォント導入と
  違い、`claude` 自体をこのスクリプトから入れる手段は無い)。
- **非公開の plugin marketplace**。steering.md の Assumptions が明示する通り、実測できているのは
  公開 marketplace のログイン不要動作だけ。非公開 marketplace を宣言した場合の挙動は未検証のまま
  §2.1 に留め、対応を作り込まない。
- **他のプログラムが所有するファイルの中身**。`~/.claude/hooks/herdr-agent-state.sh` は herdr が
  所有するので、その中身・更新方法には触れない(§4.3)。
- **宣言から消えたプラグイン/marketplace のアンインストール・登録解除**。§4.4 が決めるのは
  `enabledPlugins` / `extraKnownMarketplaces` への**追加**方向(marketplace add → plugin install)
  だけで、repo の宣言からエントリを削除したときに対応する `claude plugin marketplace remove` /
  `claude plugin uninstall` は作らない。理由: (1) この dotfiles の利用状況(1人用、年数回の対話的
  実行)では、宣言からプラグインを削除する操作自体が追加より頻度が低く、発生時に手動で
  `claude plugin uninstall` すれば足りる。(2) 残存したインストール済みプラグインは、正しくない
  ファイルが配置され続ける・古い設定が動き続けるといった実害を持たない — 単に使われなくなった
  追加物が残るだけで、Acceptance criteria が問題にしている「repo の意図と機械の状態がずれる」害とは
  性質が異なる。(3) この非対称を対象に含めるなら、追加側と同じ3分類(入れられない/すでに入っている/
  失敗)をアンインストール側にも作る必要があり、複雑さに見合わない(steering.md Rules「レビューは
  目的に錨を下ろす」)。

## 2. Assumptions & Constraints

### 2.1 What do we take as true?

- **Claude Code は両OSとも WSL / macOS 側の shell で動く**ので、`~/.claude/settings.json` の配置に
  OS 別の分岐は要らない(steering.md Assumptions)。**WSL 実機では未検証の仮定** — 根拠は今の
  statusline スクリプト冒頭のコメントが「macOS `/bin/sh` と WSL の dash の両方で動く」ことを前提に
  書かれている点のみで、herdr4mac design.md が WT の `settings.json` について持つのと同じ種類の
  留保をここでも引き継ぐ。
- Claude Code は自分の `settings.json` を書き戻す(steering.md Assumptions: 対話中に mtime が
  更新されることを実測済み)。herdr の `config.toml` や WT の `settings.json` と同じ「アプリも書くが
  dotfiles が正」の関係になるので、方式を分ける理由にならない(herdr4mac design.md §4.6 と同じ結論)。
- **`claude plugin marketplace add` / `claude plugin install` が公開 marketplace に対してログイン
  不要で通ることは実測済み**(Issue #9 のコメント: 隔離 `$HOME`、`settings.json` のみ、未ログイン
  で `lovaizu/ccpm` の add と `rn@ccpm` の install が両方成功)。
- **上の2コマンドがすでに実行済みの状態に対して冪等かどうかは未測定**。Issue #9 のコメントが実測して
  いるのは「何も無い状態から入れる」経路だけで、「もう一度同じコマンドを打ったらどうなるか」は
  試していない。この不確かさに対して本設計がどう備えるかは §4.4 で決める(結論: 事前チェックで
  回避し、コマンド自体の冪等性に依存しない)。
- **同様に、`claude plugin marketplace list` / `claude plugin list` の出力形式**(実装が事前チェック
  に使う想定のコマンド)は Issue #9 のコメントに現れた自然文の例(`No marketplaces configured` /
  `No plugins installed` / `installed, rn@ccpm 0.8.0, enabled`)以上には確認していない。機械可読な
  出力形式があるか、どう判定するのが確実かは**未測定** — steering.md の task #5 が明記している
  「隔離した `$HOME` で実測する」対象であり、本設計はその判定の**要否と結果の扱い**(severity)だけ
  を決め、具体的なコマンド/パースの実装は task #5 に委ねる。
- `statusLine` が指す `scripts/statusline.sh` は `sh <path>` として起動されるため配置先に実行ビット
  は不要で、`cp` が新規作成先に元のモードを写すことは steering.md Assumptions がすでに実測済み。
- マシンは mac 1台と Windows 1台のみ。丸ごと上書きが成立するのはこの前提の下だけで、
  「両マシンが同じ Claude Code 設定を志向する」という前提込みで初めて成り立つ。
- **`permissions.additionalDirectories` での `~` 展開は未検証の仮定**。公式ドキュメントが示す
  `additionalDirectories` の設定例は相対パス `["../docs/"]` のみで `~` の使用例が無く、他の権限
  ルール(`Read(~/Documents/*.pdf)`)や `sandbox.filesystem.allowWrite`(`~/.kube`)に `~` 展開の
  実例があっても、`additionalDirectories` 自体で同じ展開が効くかは公式ドキュメントから確認できない
  (§4.1)。task #3/#4 が隔離環境での実測で確定させる対象として残す。

### 2.2 What binds the solution?

- **配置方式を増やさない**(steering.md Rules)。管理対象はすべて既存の `deploy()`(丸ごと上書き・
  一時ファイル経由の rename・severity は `record_failure` / `warn` / 素の `echo` の3種のみ)に乗せる
  — ファイルごとの例外を作らない。これは Claude Code の設定にも例外なく適用され、`settings.json`
  の一部キーだけを差分更新する、という選択肢を最初から排除する(§5.1)。
- **`deploy()` は「読んで一部を書き換える」ことができない**。cmp -s によるバイト単位比較と丸ごと
  rename に乗っている以上、repo 側の `settings.json` は「Claude Code に持たせたいキーの全体」を
  過不足なく表現していなければならない — 拾わなかったキーは次の run で消える。これが「マシン固有の
  値」や「秘密」を `settings.json` に混ぜられない、という制約の直接の理由になる(1.4)。
- 既存の機構(`REACHED_END` 終端番兵、`HOME` の入口ガード、XDG 絶対パス検査、`deploy` が常に0を
  返す規約、大文字/小文字の命名規則)は壊さない(steering.md Rules / herdr4mac design.md §4.6)。
  本設計が追加する機構(§4.2〜§4.4)は、これらの上に積むものであって置き換えるものではない。
- `statusline.sh` はすでに `jq` に依存しており(実行時)、`jq` はこのマシンの前提としてすでに
  存在する。プラグイン宣言のパースに `jq` を使うこと(§4.4)は、`setup.sh` の実行時点で新たに
  `jq` を要求する点では新しい依存だが、`jq` というツール自体を新たに要求するわけではない。
- `~/.claude/settings.json` と `~/.claude/scripts/statusline.sh` は XDG のようなユーザー設定可能な
  base directory を持たない(Claude Code は `~/.claude/` を固定で使う、という前提 — herdr の
  `XDG_CONFIG_HOME` のような分岐は存在しない)。この前提もマシン上で確認した固定パスに基づく観測で
  あり、Claude Code のバージョンが変われば変わりうる。

## 3. Design overview

### 3.1 What is the core idea, and why does it solve the problem?

Claude Code の設定を「もう1種類の管理対象ファイル」として既存の `deploy()` に乗せ、**ファイルの
配置と、ファイルの中身が指す宣言の実体化を、はっきり別の機構として直列に並べる**。

- ファイルの配置(`settings.json` 本体、`scripts/statusline.sh`)は herdr / iTerm2 / WT と完全に
  同じ方式(丸ごと上書き・バックアップ・severity 分類)に乗る。新しい保証を作らない。
- 宣言の実体化(`enabledPlugins` / `extraKnownMarketplaces` が指すプラグインを実際に使える状態に
  する)は、ファイル配置ではなくコマンド起動なので `deploy()` には乗せない。代わりに `deploy()` が
  確立した**同じ3段階の severity 語彙**(record_failure / warn / echo)を再利用する、別の小さな
  機構として追加する。

こうすることで、「設定ファイルを置く」という今までの `setup.sh` の能力を増やさずに、「宣言と実体は
別」という Issue #9 の教訓だけを、はっきり切り分けた形で足せる。ファイル配置側の保証
(herdr4mac design.md §4.6)は無傷のまま、プラグイン実体化の失敗がファイル配置の成否を汚さない。

### 3.2 What are the pieces, and what is each responsible for?

- **`claude-code/settings.json`(新規、repo)** — `$HOME/.claude/settings.json` の原本。1で仕分けた
  repo-owned なキーのみを持つ(§4.1)。
- **`claude-code/scripts/statusline.sh`(新規、repo)** — `$HOME/.claude/scripts/statusline.sh` の
  原本。`settings.json` の `statusLine` が参照する実体で、これが無いと `settings.json` を配っても
  「Claude Code がその設定で動く」にならない(§4.1)。
- **`backup_path_for()` の改修(既存 setup.sh)** — バックアップの命名キーを「配置先の basename」
  から「repo 内の相対パス」へ変える。管理対象すべてに一律適用する(§4.2)。
- **`~/.claude/hooks/herdr-agent-state.sh` の不在チェック(新規、setup.sh)** — このファイル自体は
  管理せず、`settings.json` 配置後に存在確認だけ行い、無ければ `warn` する(§4.3)。
- **プラグイン実体化ステップ(新規、setup.sh)** — repo 側 `claude-code/settings.json` を読み、
  `extraKnownMarketplaces` を `claude plugin marketplace add` へ、`enabledPlugins` の
  `true` エントリを `claude plugin install` へ、それぞれ事前チェック付きで渡す(§4.4)。

### 3.3 How does work move?

`setup.sh` の中で、既存の herdr `config.toml` の配置(OS 分岐より前)のすぐ後ろに、Claude Code
関連の一連の処理を**OS 非分岐**で追加する(2.1: OS 分岐が要らない前提による)。順序は次の通り
— 後段が前段の結果に依存する箇所だけ直列で、それ以外は独立に失敗しうる:

1. `claude-code/settings.json` を `deploy()` で配置する。
2. `claude-code/scripts/statusline.sh` を `deploy()` で配置する(1と独立)。
3. `$HOME/.claude/hooks/herdr-agent-state.sh` の存在を確認する。無ければ `warn`(1の成否と独立 —
   1が失敗していても、していなくても同じ判定をする)。
4. 続けて既存の OS 分岐(Darwin: iTerm2 / フォント、それ以外: WSL 判定 → WT)に入る。
5. repo 側 `claude-code/settings.json` を `jq` で読み、`extraKnownMarketplaces` の各エントリに
   ついて `claude plugin marketplace add` を(事前チェック付きで)呼ぶ。すべてのマーケットプレイス
   処理が終わってから、`enabledPlugins` の `true` エントリについて `claude plugin install` を
   (事前チェック付きで)呼ぶ — marketplace が先に存在しないと install が意味を持たないための順序
   (2.1で名指しした未測定のコマンド冪等性には依存しない作り)。**この位置(既存の OS 分岐より後ろ)
   に置く理由**: `setup.sh` は `set -euo pipefail` の下で動き、既存の `deploy()` / `warn` が常に
   0を返すよう作られているのはこの `set -e` の巻き込みを避けるためである(§2.2)。新規に追加する
   このコマンド呼び出しの実装が同じ厳密さでガードし損ねた場合、その失敗が既存の OS 分岐(iTerm2/WT
   の配置、既存の再現そのもの)まで巻き込んで止めてしまうリスクがある — このステップを既存の OS
   分岐の後ろに置くことで、その巻き込みが既存の再現に及ぶ前に既存の再現を終わらせておく。
6. 最後に既存の `FAILURES` 集計へ合流する — Claude Code 関連の `record_failure` も、herdr /
   iTerm2 / WT の `record_failure` も同じ1つの配列・同じ1つの終端判定(`REACHED_END`)に乗る。

## 4. Detailed design

### 4.1 What does the claude-code/ file set guarantee, and how is a breach caught?

対象は2ファイル: `claude-code/settings.json` → `$HOME/.claude/settings.json`、
`claude-code/scripts/statusline.sh` → `$HOME/.claude/scripts/statusline.sh`。どちらも既存の
`deploy()` に、新しい配置方式を作らず乗せる。

**保証**: herdr4mac design.md §4.6 の保証がそのまま及ぶ — exit 0 で終わった run では、この2ファイル
は dotfiles の原本とバイト単位で一致し、2回流しても結果は変わらず、repo から消せばマシンからも消え、
Claude Code 自身が書き戻した値は次の run で repo の値に戻る。新しい保証を作らないことが目的であり、
新しい壊れ方も作らない。

**`settings.json` の中身についての判断(確認時点で13キー — この数字は Claude Code 自身の書き戻し
で今後も変わりうるため、検証した時点の値として扱う)**:

| キー | 分類 | 理由 |
|---|---|---|
| `model` | repo が持つ | Acceptance criteria が「使うモデル」の一致を名指ししている。値に秘密性・マシン固有性は無い |
| `hooks.SessionStart` | repo が持つ(JSONの内容として) | ファイル全体を丸ごと上書きする以上、スタンザ単位で所有者を分けられない。ただし**参照先スクリプトは対象外**(§4.3) |
| `statusLine` | repo が持つ | 参照先の `scripts/statusline.sh` も合わせて repo が持つ新規管理対象にする(Issue #9 のコメントが「両方とも repo に無いので新しい clone はどちらも得られない」と明記) |
| `enabledPlugins` / `extraKnownMarketplaces` | repo が持つ(宣言として) | 実体化は §4.4 で別扱い |
| `outputStyle` / `theme` | repo が持つ(値のみ) | 組み込み名の指定であり、対応する定義ファイルは無い(2.1)。定義ファイルを持つカスタム値は対象外(Issue #10) |
| `effortLevel` / `tui` / `skipDangerousModePermissionPrompt` / `remoteControlAtStartup` / `agentPushNotifEnabled` | repo が持つ | Acceptance criteria に個別の名指しは無いが、秘密性・マシン固有性が無く、「そのマシンと同じ設定で動く」を構成する値。丸ごと上書きである以上、個別に「対象外」と決めない限りは repo が持つ側に入る(2.2) |
| `permissions.additionalDirectories` | repo が持つ | worktree でのプラグイン開発時、プラグインが自身の参照ファイル(`references/` など)を読もうとするたびに同じ許可確認が出る構造的な摩擦がある。この許可が無いと、§4.4 が実体化したプラグインの参照ファイル読み込みで毎回確認プロンプトが出て、Acceptance criteria の「repo が宣言したプラグインが有効なものとして使える状態」を体験として損なう — この許可は §4.4 の実体化と対になって初めて意味を持つ。値は `~/.claude/plugins/cache` に固定して repo に持たせ、`~/.claude/plugins` 全体には広げない(marketplace 登録情報やインストール状態の json まで許可する具体的な必要がまだ無いため、ユーザーとの合意によりこの範囲に確定)。**ただし `~` 展開自体は未検証**: 公式ドキュメント(`settings-reference.md`)が示す `additionalDirectories` の設定例は相対パス `["../docs/"]` のみで、`~` を使った例は無い。`~` 展開の実例があるのは他の権限ルール(`Read(~/Documents/*.pdf)` など)や `sandbox.filesystem.allowWrite`(`~/.kube` の例)であり、`additionalDirectories` というキー自体で同じ展開が効くかは公式ドキュメントからは確認できていない — 「ドキュメントを読んだ」ことと「このキーで `~` 展開が実機で効くこと」は別で、後者は未実測。この点は task #3/#4 が隔離環境で `additionalDirectories: ["~/.claude/plugins/cache"]` を設定し、権限確認プロンプトが出ないことを実測して確定させる。もし `~` 展開が効かないと分かった場合は、絶対パスに置き換える案があるが、それは Windows/Mac で値が異なるマシン固有値になり repo が持てなくなるため、その場合はこのキー自体をこの設計から外す判断になる |

**マシン側に委ねる設定**: 現在のキーには該当なし。2台がまったく同じ設定を志向するという前提
(2.1)の下でのみ丸ごと上書きが成立しており、意図的にマシンごとに変えたい値は今は存在しない。
将来そのような値が必要になったら、Claude Code 自身が読む `settings.local.json`(このリポジトリは
作らない)に置く、という設計上の逃げ道だけを用意しておく(実装はしない — 今は使う先が無い)。

**秘密**: 現在のキーには該当なし(実物を確認)。理由は 1.4 に記載の通り — 丸ごと上書き・repo への
コミットという方式そのものが秘密を扱えないため、秘密性のあるキーが将来現れたら repo が持たない側に
倒す、という原則だけをここで確認しておく。

**破れの検出**: 新しい clone(`settings.json` 白紙)から `./setup.sh` を1回流し、`diff` で
`claude-code/settings.json` / `claude-code/scripts/statusline.sh` と配置先の一致を確認する。継続的
な breach 検出は既存と同じ `deploy()` の `cmp -s` による idempotency チェック(2回目の run が
`Up to date` を返すこと)に乗る — 新しい検出機構は要らない。

### 4.2 What does the backup-namespace key change guarantee, and how is a breach caught?

**衝突の実体**: 既存の `backup_path_for()` は `$BACKUP_DIR/$(basename "$dst")` という**配置先の
basename** をキーにした flat な namespace で、管理対象の basename が互いに異なることを「規約として」
前提にしている(setup.sh 内コメント、herdr4mac design.md §4.6)。`claude-code/settings.json` は
`$HOME/.claude/settings.json` に、`windows-terminal/settings.json` は WSL では
`.../LocalState/settings.json` に配られ、**どちらも basename は `settings.json`** — WSL の同じ run
で両方デプロイされる(2.1: OS 非分岐の前提)ため、この2つは今の規約のまま実装すると同じ
`$BACKUP_DIR/settings.json.<timestamp>[-N].bak` の系列に混ざる。`backup_file()` 自身の同一秒内
重複回避(`-N` サフィックス)があるので**データが上書きで消えることは無い**が、`settings.json.
20260906120000.bak` と `settings.json.20260906120000-1.bak` のどちらが Windows Terminal のもので
どちらが Claude Code のものかは、ファイル名からは判別できない。これは Acceptance criteria が名指し
している「取り出すときにそれがどの設定のものか判別できる(Claude Code と WT が同じ run で置き換え
られる状況を含む)」に反する。

**決定**: バックアップの命名キーを、**配置先の basename ではなく、管理対象の repo 内相対パス**
(`DOTFILES_DIR` を基準にした `src` の相対パス、例: `claude-code/settings.json` /
`windows-terminal/settings.json`)に変える。`$BACKUP_DIR` はその相対パスをそのままサブディレクトリ
として持つ木構造にする(例: `$BACKUP_DIR/claude-code/settings.json.<timestamp>.bak` と
`$BACKUP_DIR/windows-terminal/settings.json.<timestamp>.bak`)。

**これは全管理対象への一律適用であり、basename 規約の部分的な例外ではなく完全な置き換え**。
理由は2つ:

1. **Rules「配置方式を増やさない」**。2ファイルだけ新しい命名にして残りを basename のままにすると、
   バックアップの命名方式が2種類になり、それ自体が「ファイルごとの例外」になる。
2. **basename 規約は「convention であって実行時チェックではない」**(setup.sh 内コメント)ため、
   今後管理対象が増えるたびに人間が basename の重複を目視で確認し続ける必要がある。repo 内相対パス
   をキーにすれば、**同じ repo に同じパスのファイルは存在し得ない**というファイルシステムの性質
   そのものが一意性を保証し、規約としての運用負荷が要らなくなる — 「基準を強くする」方向の変更。

**実装上の含意**(task #3/#4 が実装するときの前提としてここに残す): `backup_path_for()` の引数は
`dst` ではなく `src`(または `src` から計算した相対パス)に変わる。呼び出し元は `deploy()` 内に
2箇所(`sweep_tmp_files` / `BACKUP_TMP` の計算)あるが、いずれも `deploy(src, dst)` のスコープ内で
`src` を直接持っている。一方で `backup_path_for()` には**もう1つの呼び出し元**があり、それは
`backup_file()` 内部(`stem="$(backup_path_for "$dst")..."` の行)——`backup_file(dst, tmp)` という
署名のとおり `src` も repo 内相対パスも一切持たない。つまり「呼び出し元は既に `src` を持っている
ので新しい情報は要らない」とは言えず、`backup_file()` 自身の呼び出し箇所には新しい情報を渡す
必要がある。具体的な渡し方は2通りが考えられる:(a) `backup_file()` の署名に repo 内相対パス
(またはバックアップの計算済みベースパス)を受け取る引数を追加し、`deploy()` が自分の `src` から
計算して渡す、(b) `deploy()` 側でネスト後のバックアップパスまで事前に計算しておき、
`backup_file()` は内部で `backup_path_for()` を呼ばずにその計算済みパスをそのまま受け取って使う。
どちらを取るかは実装タスク(#3/#4)が具体的に決める — ここでは「`deploy()` の2箇所は新しい情報を
要らないが、`backup_file()` 内部の呼び出し箇所には新しい情報を渡す必要がある」という前提の訂正だけ
を残す。`backup_file()` が現在 `mkdir -p "$BACKUP_DIR"` を呼んでいる箇所は、計算後のバックアップ
パスの親ディレクトリ(ネストしうる)に対する `mkdir -p` に変える。`sweep_tmp_files` / `tmp_for` は
パス文字列に対して汎用に動くため、ネストしても変更不要。setup.sh 内の「BACKUP_DIR is one flat
namespace keyed by basename」というコメント(および herdr4mac design.md §4.6 参照部分)は、この
変更を実装する際に古い規約を指したまま残さないよう、実装タスクで書き換える必要がある。

**既存バックアップへの影響**: 変更前に basename 方式で取られたバックアップは、そのままの名前で
`$BACKUP_DIR` 直下に残る(読み書きしない・削除しない)。変更後の run が新しい木構造の下に新しい
バックアップを作るだけなので、過去のバックアップを上書きしたり読めなくしたりしない — 移行は
一方向かつ非破壊的。

この一律適用により、herdr の `config.toml` や iTerm2 の `herdr.json` のバックアップも、今後は
`$BACKUP_DIR/config.toml.<timestamp>[-N].bak` / `$BACKUP_DIR/herdr.json.<timestamp>[-N].bak` という
古い flat な置き場所から、`$BACKUP_DIR/herdr/config.toml.<timestamp>[-N].bak` /
`$BACKUP_DIR/iterm2/herdr.json.<timestamp>[-N].bak` のようなネストした置き場所に変わる。変わるのは
バックアップの**置き場所**だけであり、これら自身の配置先・冪等性・失敗時の挙動という herdr4mac
design.md §4.6 が既に保証している再現性には一切影響しない。

**破れの検出**: WSL 相当の環境(隔離 `$HOME` + `windows-terminal/settings.json` と
`claude-code/settings.json` の双方に既存ファイルを置いた状態)で `./setup.sh` を1回流し、
`$BACKUP_DIR/windows-terminal/` と `$BACKUP_DIR/claude-code/` の両方にそれぞれ1件ずつバックアップ
が作られること、互いの内容を上書きしていないことを確認する。継続的な検出は既存と同じ
`backup_file()` の同一秒内重複回避に乗る(この節が変えるのはキーの計算だけで、重複回避ロジック
自体はそのまま)。

### 4.3 What does excluding herdr-agent-state.sh guarantee, and how is a breach caught?

`~/.claude/hooks/herdr-agent-state.sh` はヘッダーコメントに "installed by herdr" / "managed by
herdr; reinstalling or updating the integration overwrites this file. add custom hooks beside this
file instead of editing it." と明記されている(確認済み)— **herdr 自身の Claude Code 連携インス
トーラが所有・上書きするファイル**であり、このリポジトリが原本を持つファイルではない。

**決定**: このファイルを管理対象にしない。repo にコピーを置かず、`deploy()` を呼ばない。

**理由**: `deploy()` の丸ごと上書きは「1つの配置先には1つの書き手」を前提にしている(方式は1つ、
例外は無い、という Rules の裏返し)。もしこのファイルを repo でも管理したら、herdr の連携を
再インストール/更新するたびに herdr がこのファイルを上書きし、次に `./setup.sh` を流すと dotfiles
がまた上書きし返す — どちらの上書きも相手の変更を検出せず、無言で取り合いになる。これは
herdr4mac design.md §4.6 が「アプリ自身も書くファイル」(herdr の `config.toml` や WT の
`settings.json`)について「dotfiles が正」と決めたのと**同じ構図に見えて実は違う** — あちらは
「アプリが表示上の値を書き戻すが、それを dotfiles の値に戻すこと自体が目的」だったのに対し、
`herdr-agent-state.sh` は**中身そのものが herdr のバージョンに紐づくロジック**(ヘッダーの
`HERDR_INTEGRATION_VERSION=7` が示す通り)で、dotfiles 側が「正しい中身」を知る立場にない。

**このファイルが無い機械での挙動**: `settings.json` の `hooks.SessionStart` はこのパスを無条件に
参照する(`bash "$HOME/.claude/hooks/herdr-agent-state.sh" session`)。herdr の連携がまだ入って
いない機械では、`settings.json` を配置した直後にこのパスが存在しない状態になりうる。

**決定: `warn` する(黙らない・`record_failure` にもしない)**。`settings.json` を配置した直後に
`[ -e "$HOME/.claude/hooks/herdr-agent-state.sh" ]` を確認し、無ければ warn で「SessionStart フック
は herdr 自身の Claude Code 連携に依存しており、この dotfiles はそれを入れない。herdr 側の連携を
インストール(または更新)してから `./setup.sh` を再実行して確認せよ」と伝える。

- **`record_failure` にしない理由**: 管理対象(`settings.json`)自体は正しく配置されており、
  herdr4mac design.md §4.6 の3形態の使い分け(「管理対象が届かなかった」ときだけ `record_failure`)
  に従えば、このケースは該当しない。
- **黙らない理由**: このケースを検出せず放置すると、フックの実行は毎セッション開始時に静かに
  失敗し続ける(あるいは Claude Code 側が何らかの形でエラーを出すかもしれないが、その表示形式は
  未確認)。iTerm2 の「herdr プロファイルが既定になっていない」警告(herdr4mac design.md §4.5)と
  同じ構図 — 配置は正しく終わっているのに、外部の前提が満たされていないと効果が出ない設定がある
  ときに warn で言う、という既存の severity 語彙をそのまま再利用する。
  **本設計はここで、フックの呼び出し失敗が Claude Code のセッション自体を壊さない(起動できる・
  使える)ことを前提にしているが、これは実機で未検証の仮定である**。setup.sh 側が exit 0 で終わり
  warn を出すことは保証できても、`hooks.SessionStart` の呼び出し先が無い状態で Claude Code 自身が
  壊れないかどうかは別の話で、この設計はそれを確認していない。steering.md の Acceptance criteria
  「dotfiles が原本を持たない設定を壊さない…それが無いマシンでも Claude Code が壊れた状態に
  ならず、必要なものがあるなら読み手にそれが分かる」の「壊れた状態にならず」の部分が、まさにこの
  未検証点そのものである。steering.md task #4 の「隔離した `$HOME` で実測する」ステップ(「他の
  プログラムが所有する設定が無い環境」を実測対象に挙げている)が、この未検証点を確かめる場になる。

**この判断の前提となる未検証の点**: 両マシンとも herdr の Claude Code 連携を使う、というのは
本設計が置く前提であり、もしこの前提が崩れたら(将来一方の機械で herdr 連携を
使わなくなったら)、`hooks.SessionStart` のスタンザ自体を repo の `settings.json` から外すという
別の判断が要る — それは本設計の対象外で、そのときの `design.md` 更新で扱う。

**破れの検出**: 隔離 `$HOME`(`herdr-agent-state.sh` を置かない状態)で `./setup.sh` を1回流し、
`settings.json` は配置されつつ(exit 0 に寄与)、上記の warn が stderr に出ることを確認する。
`herdr-agent-state.sh` を置いた状態で同じ run を流し、warn が出ないことも確認する。

### 4.4 What does the plugin realization step guarantee, and how is a breach caught?

repo 側 `claude-code/settings.json` の `extraKnownMarketplaces` / `enabledPlugins` は**宣言**であり、
`claude plugin marketplace add <repo>` / `claude plugin install <plugin>@<marketplace>` という
**コマンド呼び出し**だけが実体(`~/.claude/plugins/` 配下の `known_marketplaces.json` /
`installed_plugins.json` / `marketplaces/`)を作る(Issue #9 のコメントで確認)。この実体そのものは
repo が持たない — **マシン側に委ねる**(コマンドを再実行すれば毎回同じ実体が再現できる、という
意味で「委ねて壊れない」)。宣言(`settings.json` の中身)だけが repo の原本であり、実体化コマンドは
その原本を読んで動く**単一の入力源**にする(marketplace/plugin の一覧を setup.sh 側に別途書かない
— §5.1)。

**ファイル配置とは別の機構にする理由**: `deploy()` は「ファイルを丸ごと置き換え、cmp -s で idempotent
性を測る」ことに特化しており、コマンドの成功/失敗/冪等性はこの型に合わない。無理に `deploy()` を
経由させると、「配置されたかどうか」を判定する `cmp -s` に相当するものが無いコマンド実行を、
ファイル配置の関数に混ぜることになり、§4.6 が置いた「`deploy()` は常に0を返す」という契約の意味が
薄れる。そこで**別の小さな機構**として追加するが、**severity の語彙は増やさない** — 既存の
`record_failure` / `warn` / 素の `echo` をそのまま使う。

**severity の割り当て(3つの環境それぞれで run がどう終わるか)**:

1. **実体を入れられない環境**(`claude` コマンドが無い、または `jq` が無い)→ **`warn`**、run は
   このステップ単体では非0にならない(他が全部成功すれば exit 0 で終わる)。理由: `claude` /
   `jq` はこの repo が配布・インストールするものではなく(1.4)、Homebrew が無い機械でのフォント
   導入(herdr4mac design.md §4.5、`warn` かつ管理対象ではないので失敗集計に数えない)と同じ
   「外部の前提ツールが無い」というカテゴリ。warn は「`claude`(または `jq`)を入れてから
   `./setup.sh` を再実行せよ」と言う。**プラグインは管理対象ファイルではない**ので、herdr4mac
   design.md §4.5 のフォントと同じ扱いにする — ただし後述の3.のように、`claude` が存在して
   コマンドが失敗した場合は扱いが変わる(フォントと違う所以)。
2. **すでに入っている環境**(precheck で marketplace / plugin がすでに存在すると分かる)→
   **素の `echo`**(FYI)。`brew list --cask font-hackgen-nerd &>/dev/null` → 既存なら
   `"already installed. Skipping."` という既存の idiom をそのまま踏襲する。severity を上げない
   理由: 何も変える必要が無く、読み手に求めることも無い(herdr4mac design.md §4.6 の3形態の使い
   分け基準そのもの)。
3. **入れようとして失敗した環境**(`claude` はあるのに `marketplace add` / `install` が非0で
   終わる)→ **`record_failure`**、run は非0で終わり、末尾の失敗一覧に名指しで載る。理由:
   Acceptance criteria が「repo が宣言したプラグインが有効なものとして使える状態」を、モデル名や
   statusLine の表示と**同じ並びで**新しいマシンでの再現条件に挙げている — フォントと違い
   「入らなくても実害が無い」と明言された任意要素ではなく、明示的な再現対象そのものなので、
   ファイル配置の失敗と同格の severity を与える。ここでの `record_failure` は herdr4mac design.md
   §4.6 の『配る先を持っていた管理対象が、そこに届かなかった』というファイル配置の基準の適用では
   ない — 対象はファイルではなくコマンド呼び出しであり、この設計での `record_failure` は
   『Acceptance criteria が明示する再現対象が実現したか』という別の基準に基づく適用である。

**この3分類がなぜ「未測定のコマンド冪等性に依存しない」設計になっているか**(2.1で名指しした
未検証点への対処): 2.と3.の分岐を「まず実行してみて、返ってきたエラーが `already exists` 相当か
本当の失敗かを判定する」方式にすると、`claude plugin marketplace add` / `install` の**エラー文言や
終了コードの意味**を知っている必要があるが、これは未測定。代わりに**先に現在の状態を確認してから
実行する**(precheck-then-invoke、既存の brew の idiom と同型)ことで、コマンド自体が2回目の
呼び出しに対して冪等かどうかを知らなくても、この3分類が成立する。ただし precheck に使う具体的な
コマンド・出力の読み方(`claude plugin marketplace list` / `claude plugin list` の正確な形式)は
Issue #9 のコメントにある自然文の例以上には確認できておらず、**未測定のまま残す** — steering.md
task #5 の「隔離した `$HOME` で実測する」がこれを確定させる場であり、本設計はその判定の
存在・返す先(severity)だけを決める。

**実行順序の保証**: `extraKnownMarketplaces` の全エントリへの `marketplace add` 処理を終えてから
`enabledPlugins` の `true` エントリへの `install` 処理に入る。`install` は対象の marketplace が
先に登録されていることを前提にすると考えられるため(`plugin@marketplace` という表記そのものが
依存関係を表している)。

**`enabledPlugins` の `false` エントリは実体化の対象にしない**。Acceptance criteria の文言が
「有効なものとして使える状態」("有効な"に係る)なので、無効宣言のプラグインを持つ必要は無いと
判断する。現在のデータには `false` のエントリが無く、この判断は今のところ検証を要しない
(将来 `false` のエントリが増えたときに再検討する)。

**破れの検出**: 隔離 `$HOME` で以下の4パターンを実測する(task #5 のステップそのもの) —
(a) `claude` / `jq` が無い状態、(b) marketplace・plugin ともに未導入の状態、(c) すでに導入済みの
状態、(d) 何らかの理由で `add` / `install` が失敗する状態(例: ネットワーク遮断)。それぞれが
上記1〜3のどの経路をたどり、run がどの exit code で終わるかを確認する。

**宣言からの削除(アンインストール・marketplace 登録解除)は対象外** — 理由は1.4。

## 5. Alternatives considered

### 5.1 Why this shape, and not another?

- **`settings.json` を丸ごとではなくキー単位で差分マージする案は採らない**。実現には
  `deploy()` の cmp -s ベースの idempotency 判定を JSON レベルのマージに置き換える必要があり、
  これは「配置方式を増やさない」という Rules に反する新しい方式そのものになる。現在の
  `settings.json` に repo が持たないキー(マシン固有値・秘密)が無い(§4.1)以上、この複雑さを
  正当化する具体的な必要が無い。
- **プラグインの marketplace/plugin 一覧を `setup.sh` 側に別途ハードコードする案は採らない**。
  `settings.json` の `extraKnownMarketplaces` / `enabledPlugins` という既存の宣言と二重の情報源に
  なり、片方だけ更新して食い違う(herdr4mac design.md §4.5 の Guid 二重リテラルが持つのと同種の
  破れ方)。repo 側 `settings.json` を単一の入力源にして `jq` で読む方が、ズレの余地そのものを
  無くす。
- **プラグイン実体化を `deploy()` に無理に押し込む案は採らない**(§4.4 に既述)。コマンド呼び出し
  はファイルの cmp -s / rename という `deploy()` の型に合わず、`deploy()` の「常に0を返す」契約を
  曖昧にする。既存の severity 語彙(record_failure / warn / echo)だけを再利用した別の小さな
  機構にする方が、`deploy()` 自体の保証(herdr4mac design.md §4.6)を汚さない。
- **バックアップ衝突を「2ファイルのうち片方だけ命名を変える」パッチで解消する案は採らない**。
  これは「配置方式を増やさない」という Rules に対する部分的な例外そのものになり、次に basename が
  衝突する管理対象が増えるたびに同じ判断をやり直すことになる。repo 内相対パスへの一律変更
  (§4.2)は、ファイルシステムが一意性を保証する形にすることで、この種の判断自体を将来不要にする。
- **配置先の basename を変える(Windows Terminal か Claude Code のどちらかのファイル名を変える)
  案は採らない**。どちらの basename も、それを読むアプリ(Windows Terminal / Claude Code)側が
  固定で期待する名前であり、dotfiles 側の都合で変えられるものではない。

### 5.2 What did we trade away?

- **`$BACKUP_DIR` は flat な1階層ではなくなり、repo の構造を映した木構造になる**(§4.2)。
  手でバックアップを探すときに1つのディレクトリを一覧するだけでは済まなくなるが、年数回しか
  流さない・失敗すればすぐ気づく、という利用状況(steering.md Rules「レビューは目的に錨を下ろす」)
  では実害が無いと判断した。
- **`setup.sh` は実行時に新たに `jq` を要求する**(プラグイン宣言のパース、§4.4)。`jq` はすでに
  `statusline.sh` の実行時依存として存在するので、環境に新しいツールを増やすわけではないが、
  `setup.sh` 自身の実行にツール依存が増えるのは事実 — `claude` / `jq` 不在を `warn` で扱う
  (§4.4)ことで、依存が満たせない機械でも run 全体が exit 0 で終われるようにして、この代償を
  吸収している。
- **非公開 marketplace・`false` 宣言されたプラグインの実体化は作り込まない**(1.4、§4.4)。
  現在のデータにも Assumptions にも登場しない組み合わせのために複雑さを先取りしない、という判断。
  必要になった時点で、この design.md を改訂して対応する。
- **プラグインが実際に「使える」ことの検証は、コマンドの終了コードより深いところまでは行わない**。
  `claude plugin install` が0で終わったことをもって成功とみなし、それ以上(実際に有効化されて
  動くか)は確認しない — iTerm2 の既定プロファイル警告やフォント導入と同じ深さの検証に揃えている。
