# herdr4mac — design notes

Not read at runtime — for whoever maintains the design and needs to judge whether a decision is still
right when requirements change.

## 1. Background & Goals

### 1.1 What is the goal?

dotfiles の目的(Win / Mac の端末環境を clone → setup 一発で再現し、毎回設定しない)に沿って、
Mac(iTerm2)対応を追加し、Win(Windows Terminal)側も含めて設定を統一仕様
(テーマ・フォント・herdr 操作・即時切替キー・⇧Enter)に揃える。
あわせて、同じ「clone → setup 一発」の対象に Claude Code のユーザー設定
(`~/.claude/settings.json` とステータスライン用シェル)を加える。

### 1.2 What goes wrong without this?

Mac では herdr の workspace / agent 切替に毎回プレフィックス2ストロークが必要で Win と操作感が
揃わず、テーマ・フォントも手動設定になる。また統一仕様が明文化されていないと、OS ごとの設定が
それぞれ独自に育って再び乖離する。

### 1.3 What does reaching it require?

統一仕様の明文化(README の対応表)、iTerm2 側のキー→バイト列マッピングと色・フォントの
プロファイル定義、WT 側の別名チョード整理、それらを OS 判定つきでインストールする setup.sh。
加えて Claude Code のユーザー設定をホーム非依存の形で持ち、setup.sh の共通部から配置すること。

### 1.4 What is out of scope?

herdr 本体・iTerm2 のインストール、Win 側フォントのインストール(WSL からは不可能 — README の
手動手順に委ねる)、シェルの統一(Win は PowerShell / WSL bash、Mac は zsh のまま — herdr の中の
体験が揃えば足りる)、iTerm2 のプロファイル外グローバル設定の管理、Claude Code の
`~/.claude` 配下のうち settings.json / statusline.sh 以外(プラグイン実体・履歴・
認証情報・herdr 統合フックの本体・output-styles・カスタムテーマ)。

## 2. Assumptions & Constraints

### 2.1 What do we take as true?

herdr の config.toml は OS 共通(XDG パスも共通、未検証)。HHKB では Windows の Alt 位置のキーが
Mac では Cmd — よって Win の ctrl+alt 系は Mac では ⌃⌘ 系が同じ指運びになる。iTerm2 は `⌃T` を
既定で奪わない(⌘T が新タブ)ため、WT で必要だった「ctrl+t 無効化」に相当する設定は不要。
WT の ctrl+shift / alt+shift 別名チョードは使われておらず削除してよい(ユーザー確認済み)。

### 2.2 What binds the solution?

iTerm2 は WT のような単一の可搬な settings.json を持たず、設定は `com.googlecode.iterm2.plist` に
集約される — dotfiles で扱うにはファイル1個で完結し、起動中でも安全に読み込める仕組みが要る。
setup は Win 側も WSL の bash で実行される前提(既存 setup.sh の方式)なので、両OSとも bash 1本の
エントリで書ける。配置はシンボリックリンクを張らずファイルの実体を置く(既存 setup.sh の方式)。
配置先のうち herdr の config.toml・Claude Code の settings.json・WT の settings.json はアプリ自身も
書き戻すが、**dotfiles が正**なので方式は分けない — 管理対象はすべて丸ごと上書きする(§4.7)。
アプリが書き戻した値(herdr のテーマ名、Claude Code が `/config` で書いた設定)は次の setup で
dotfiles の値に戻り、WT が WSL ディストロごとに生成するプロファイルは WT 自身が作り直す。

## 3. Design overview

### 3.1 What is the core idea, and why does it solve the problem?

「共通層+OS別層」の2層構成にする。共通層 = herdr config と統一仕様(README の対応表)。
OS別層 = その仕様を各ターミナルの語彙に翻訳した設定ファイル(WT の settings.json / iTerm2 の
Dynamic Profile)。仕様を README に1か所で明文化することで、両OSの設定が同じ使い勝手に収束し、
将来の変更も「仕様を直す → 両OSの翻訳を直す」という手順に固定される。iTerm2 側は
**Dynamic Profiles**(`~/Library/Application Support/iTerm2/DynamicProfiles/` に置いた JSON を
自動読み込み)を使う — キー・色・フォントがプロファイル単位で JSON 1ファイルに収まり、既存の
コピー方式にそのまま乗る。

### 3.2 What are the pieces, and what is each responsible for?

- `README.md` — 統一仕様の源: 操作×OS別キー対応表、テーマ・フォント、セットアップ手順。
- `herdr/config.toml` — OS 共通の herdr 設定(本セッションでは不変)。
- `windows-terminal/settings.json` — 統一仕様の Win 翻訳(ctrl+alt 系のみに整理)。
- `iterm2/herdr.json` — 統一仕様の Mac 翻訳(⌃⌘ 系 + ⇧Enter + Gruvbox Dark + HackGen)。
- `claude/settings.json` — Claude Code のユーザー設定。ホーム依存パスは `"$HOME/…"` で記述。
- `claude/scripts/statusline.sh` — ステータスライン生成スクリプト(ホーム非依存、そのまま配置)。
- `setup.sh` — 単一エントリ: 共通部(herdr + Claude Code)→ `uname` で分岐 → darwin(iTerm2 配置+
  brew があればフォント)/ WSL(WT 配置)。

### 3.3 How does work move?

両OSとも `./setup.sh` を実行 → 共通部が herdr config と Claude Code 設定を配置 → OS 判定 → darwin なら Dynamic
Profile 配置(iTerm2 が監視していて再起動不要で反映)+フォント、WSL なら WT の settings.json を
配置。使い勝手を変えたいときは README の仕様を先に直し、両翻訳ファイルを追随させる。

## 4. Detailed design

### 4.1 What does the README spec guarantee, and how is a breach caught?

保証: 両OSのキー割り当て・送信バイト列・外観の単一の正が存在し、設定ファイル間の乖離を判定できる。
破れの検出: 各タスクの completion criteria が「README の対応表と一致」を要求しており、照合は
タスク検証(checks/)で記録される。将来の変更では README と両翻訳の diff が同一 PR に並ぶことで
乖離が見える。

### 4.2 What does the iTerm2 Keyboard Map guarantee, and how is a breach caught?

保証: `⌃⌘[`/`⌃⌘]`/`⌃⌘U` が herdr のプレフィックス列(0x14 + 文字)、`⇧Enter` が `\n` を送信する。
エントリは iTerm2 の `0x<keycode>-0x<modifier flags>` 形式、アクションは Send Escape Sequence /
Send Text。破れの検出: 作成時のキーコード手計算照合(タスク#2)と、ユーザーの実機確認(タスク#5)。
macOS / iTerm2 既定とは ⌃⌘ 系・⇧Enter とも衝突なし(⌃⌘F フルスクリーンとは別キー)。

### 4.3 What does the Dynamic Profile guarantee, and how is a breach caught?

保証: JSON が valid で Guid / Name を持てば iTerm2 が自動登録し、Guid 固定なので再コピー時も同一
プロファイルの更新になる(重複しない)。破れの検出: JSON 構文エラー時はプロファイルが現れない —
タスク#2 の `json.tool` 検証とタスク#4 の配置確認で事前に捕捉する。

### 4.4 What does the WT cleanup guarantee, and how is a breach caught?

保証: 即時切替は `ctrl+alt` 系3キーのみになり、README の対応表と1:1 になる。⇧Enter・`ctrl+t`
無効化・WT 固有キー・外観・プロファイルは従来のまま。配置は丸ごと上書きなので(§4.7)、dotfiles から
消したチョードと、それが指していた未使用 action は、配置先からも消える。破れの検出: タスク#3 で
削除対象以外に diff がないことと未使用 action が残らないことを照合。実機は次回 Win 同期時の
ユーザー確認(タスク#5 で依頼)。

### 4.5 What does the setup.sh OS dispatch guarantee, and how is a breach caught?

保証: darwin では WT ブロック(`wslpath`/`cmd.exe` 依存)に到達せず、brew 不在でもエラー終了しない。
WSL では従来と同じファイルを同じ場所に配置する。WSL でない Linux — `uname -s` は同じ `Linux` を返すので
分岐だけでは区別できない — では `wslpath` / `cmd.exe` の不在を先に確かめ、無ければ WT をスキップして
続行する。`cmd.exe` が答えを返さない場合も同じくスキップで、`wslpath` を空の引数で呼ぶことはない。
破れの検出: mac での実行テスト(exit 0 + 配置確認、brew 分岐のメッセージ)と、`uname` / `wslpath` /
`cmd.exe` のスタブで WSL 経路・非 WSL Linux 経路に到達させる実測(タスク#4 / #10)。

### 4.6 What does the Claude Code settings deployment guarantee, and how is a breach caught?

保証: 両OSで同じ Claude Code のユーザー設定(出力スタイル・努力度・テーマ・プラグイン・
ステータスライン・herdr の SessionStart フック)が再現され、ホームディレクトリのパスが
OS ごとに異なっても正しい実パスを指す。

仕組み: settings.json の `command` はシェル経由で実行される — Claude Code 2.1.241 のバイナリで検証済み
(hook `command` スキーマの説明が "When absent [args], `command` runs through a shell (bash on POSIX,
PowerShell on Windows without Git Bash)" と述べ、statusLine も同じランナー `Oes(…,"StatusLine",…)` を
通る)。よって dotfiles 側は `"$HOME/…"` を直接書き、setup.sh はパスの変換をせずそのまま配置する
(settings.json も statusline.sh も §4.7 の `backup_then_copy` で丸ごと配置する)。
ホームパスに空白が含まれても壊れないよう、両 command のパスはダブルクォートで囲む。

当初はプレースホルダ(`__HOME__`)+ setup 時の置換を採る設計だったが、`$HOME` 展開が検証できたため
不採用にした。置換方式は sed の置換文字列側で `&` がマッチ全体に解釈されるなど無言で壊れる失敗モードを
持ち込むため(実測: ホームが `/home/a&b` だと `/home/a__HOME__b` になる)、機構を持たない方が堅い。

境界: `~/.claude/hooks/herdr-agent-state.sh` は herdr の統合インストーラが管理するファイル
(冒頭に "managed by herdr" と明記され、再インストールで上書きされる)なので dotfiles では持たない。
settings.json 側の SessionStart エントリだけを持ち、本体不在なら setup.sh が警告する。
`~/.claude/output-styles/sleek.md` も持たない — 現行 settings.json が参照していない
(`outputStyle` は組み込みの `Concise`)ため。

`~/.claude/themes/` のカスタムテーマも持たない。`theme` を組み込みの `light` にしたため
参照が無くなったからで、これは「設定名は運べても実体が運べていない」型の破れ(カスタムテーマ名だけが
他PCに渡ると Claude Code は警告なく組み込みにフォールバックする)を、実体を運ぶのではなく
組み込みテーマだけを使うことで回避する選択でもある。

テーマは3層あり、層ごとに持ち主が違う:

| 層 | 値 | 持ち主 |
|---|---|---|
| 端末そのものの配色 | Gruvbox Dark | Win: `windows-terminal/settings.json` の `profiles.defaults.colorScheme` / Mac: `iterm2/herdr.json` の色定義 |
| herdr の UI | `gruvbox-light` | `herdr/config.toml` の `[theme] name` |
| Claude Code の UI | `light`(組み込み) | `claude/settings.json` の `theme` |

端末だけ暗くしても herdr / Claude Code の UI は追随しない。herdr が light なのはワークスペースの
選択状態を判別しやすくするためで、暗い端末の上に明るい UI が乗る組み合わせは意図されたもの。

前提: statusline.sh は `jq` に依存する。不在時は exit 0 のまま ` |  | dir@branch` を返して無言で
劣化するため、setup.sh が `jq` の存在を確認して警告する(mac は OS 同梱だが Ubuntu/WSL は既定で不在)。

破れの検出: 配置後の settings.json が dotfiles の原本とバイト単位で一致すること(タスク#7 / #10 —
丸ごと上書きなので `diff` 1本で判定できる)、原本との diff 照合(タスク#6)、`/config` 上での
`remoteControlAtStartup` の目視確認(タスク#7)。

### 4.7 What does the whole-file overwrite guarantee, and how is a breach caught?

対象: 管理対象のファイルすべて — herdr の `config.toml`、Claude Code の `settings.json` と
`statusline.sh`、iTerm2 の Dynamic Profile、WSL では WT の `settings.json`。**配置方式は1種類だけで、
ファイルごとの例外を持たない**。アプリ自身も書くファイルかどうかは方式を分ける理由にならない。

保証: **配置後のファイルは dotfiles の原本とバイト単位で一致する**。dotfiles が持つ値がそのマシンの
値になり、dotfiles から消した設定はマシンからも消え、同じ dotfiles で2回流しても結果は変わらない
(冪等)。アプリが書き戻した値 — herdr のテーマ名と `onboarding`、Claude Code が `/config` で書いた
設定 — は次の setup で dotfiles の値に戻る。これは副作用ではなく目的で、「clone → setup 一発で同じ
環境」が意味を持つのはこの向きのときだけ。

実装は `setup.sh` の `backup_then_copy` 1つ。既存の配置先は BACKUP_DIR に退避してから置き換える。
退避は**このマシンを dotfiles に載せ替える最初の1回のため**のもので、配置先が既に原本と同一なら
何も書かず退避も取らない — さもないと再実行のたびに、リポジトリにあるファイルと同じ中身の `.bak` が
1つずつ積み上がる。恒常的なバックアップ機構は持たない(履歴が要るなら git にある)。

代償: 配置先にしか無い設定は消える。**残したいものは dotfiles に入れる**、が唯一の運用で、手元で
`/config` や herdr の UI から変えたものを dotfiles へ戻す作業はユーザーに残る(§5.2)。

境界: 上書きするのは上の管理対象だけで、同じディレクトリにある他のもの(`~/.claude` の `sessions/`
`projects/` `history.jsonl` `plugins/`、iTerm2 の他の Dynamic Profile、WT が別ファイルに持つ状態)は
別ファイルなので巻き込まない。WT の `settings.json` だけは配置先の全体が置き換わるため、そのマシンの
WSL ディストロのプロファイルも一度消える — WT が起動時に作り直す。

破れの検出: mac 上での実行(exit 0、配置した4ファイルが原本と `diff` で一致、2回流してバイト列が
変わらない、配置後の `herdr config check` が通る)と、WSL / 非 WSL Linux 経路の `uname` `wslpath`
`cmd.exe` スタブでの到達確認を、タスク#10 の検証に記録する。判定が `diff` 1本で済むこと自体が
この方式の検出手段で、方式が増えれば増えた分だけ検出は難しくなる。

この節は当初、アプリも書くファイルを項目単位でマージする機構を規定していた(#9 / #13 で実装)。
撤回して上書きに統一した経緯は §5.1。

## 5. Alternatives considered

### 5.1 Why this shape, and not another?

- **setup を OS 別ファイルに分割(setup-mac.sh / setup-win.sh)**: エントリが2つになり
  「どれを実行するか」を README で説明する手間が増える。共通部(herdr)が重複するか相互 source に
  なり、リポジトリの規模に対して構造が重い。`uname` 分岐つきの単一 `setup.sh` なら両OSとも
  同じコマンドで済む(Win 側も WSL bash で実行する既存前提に乗る)。
- **「Load preferences from custom folder」+ plist 全体管理**: iTerm2 の全設定を奪い、plist は
  バイナリ化・頻繁な書き戻しで diff が汚れる。必要なのは1プロファイル分だけなので過剰。
- **`defaults write` の羅列**: Keyboard Map の入れ子 dict が壊れやすく、iTerm2 起動中の書き込みは
  上書きされ得る。
- **Karabiner-Elements でキー変換**: 端末外のグローバル常駐が増え、iTerm2 以外にも効く。端末内で
  完結する Dynamic Profiles が最小。
- **WT の別名チョードを Mac にも展開**: 統一の方向と逆(使われていない別名を増やす)。むしろ Win 側を
  ctrl+alt 系のみに整理して両OSを1:1 にする。
- **`~/.claude` ごとシンボリックリンク**: プラグインキャッシュ・履歴・認証情報など Claude Code が
  実行時に書き込む大量のファイルを巻き込む。管理したいのは settings.json と statusline.sh の2つだけ。
- **settings.json をそのまま(リテラルの絶対パスのまま)持つ**: mac(`/Users/kiyo`)と WSL
  (`/home/kiyo`)でホームパスが異なるため片方で壊れる。
- **`__HOME__` プレースホルダ + setup 時の sed 置換**: `$HOME` 展開が検証できた今では余分な機構。
  sed は置換文字列側の `&` `\` やデリミタ文字で無言で壊れ、しかも結果は有効な JSON のままなので
  検出しづらい。採らない。
- **herdr のフックスクリプト本体も dotfiles で持つ**: herdr の統合が再インストール時に上書きする
  ため二重管理になり、バージョン不整合を招く。
- **アプリも書くファイルは項目単位でマージする**(dotfiles が持つキーだけを dotfiles の値にし、
  配置先にしか無いキーは残す): 一度は実装し(`lib/merge.py` — #9 / #13)、撤回した。守ろうとしていた
  「そのマシンにしか無い設定」を数え上げると、WT が WSL ディストロごとに書くプロファイルは WT 自身が
  作り直すマシンの目録であり、herdr が書き戻すテーマ名と `onboarding` は**上書きで直したい値そのもの**
  だった(指定したテーマが herdr の書き戻しで戻り続けるのが #12 の中身)。守る対象が実在しない一方で
  費用は大きく、`jq` にも `tomllib` にも依存せず JSON / TOML を自前で読み書きし、アプリが要素を書き足す
  配列を id で突き合わせる機構が要る。この会話で見つかった不具合 — 同じ matcher のフック消失、id の
  大小文字の畳み込み、`keybindings` のチョードだけが消える、空の `themes` が配置先のテーマ定義を削除
  する、意図的に消した action の復活、`[[keys.command]]` があると何も配られない、冪等性違反 — は
  すべてこの機構だけが原因だった。決め手は**マージに削除の概念が無い**こと: dotfiles からキーを消しても
  配置先からは消えないので、「dotfiles が正」をそもそも満たせない。上書きなら方式は1種類、検証は
  `diff` 1本になる。

### 5.2 What did we trade away?

Dynamic Profile はデフォルトプロファイル化を自動でできない(初回に iTerm2 UI で一度設定する手作業が
残る)。Win 側フォントは自動化されない(WSL から Windows へのフォントインストールは不可 — README の
手動手順で受容)。シェルは OS ごとに異なるまま(統一しない判断)。グローバルな iTerm2 設定
(ウィンドウ挙動等)は管理対象外のまま。配置は一方向(dotfiles → ホーム)の丸ごと上書きに割り切った
ので、手元で変えた設定(Claude Code の `/config`、herdr のテーマ選択、WT の設定 UI)を dotfiles へ
戻す作業は手動で残り、戻す前に setup を流せばその変更は失われる — 退避された `.bak` から手で拾うことに
なる。方式を1種類に保つ代わりに、この一手間を受け入れた。
