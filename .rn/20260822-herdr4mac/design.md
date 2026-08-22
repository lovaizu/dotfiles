# herdr4mac — design notes

Not read at runtime — for whoever maintains the design and needs to judge whether a decision is still
right when requirements change.

## 1. Background & Goals

### 1.1 What is the goal?

WSL の herdr + Windows Terminal 環境(プレフィックス列の一発送信キーバインド、⇧Enter 改行、
Gruvbox テーマ、HackGen フォント)を macOS の iTerm2 で再現し、dotfiles + setup.sh で
インストール可能にする。

### 1.2 What goes wrong without this?

Mac では herdr の workspace / agent 切替に毎回プレフィックス(`^T` → キー)の2ストロークが必要になり、
Windows 側と操作感が揃わない。テーマ・フォントも手動設定になり、環境再構築のたびに手作業が発生する。

### 1.3 What does reaching it require?

iTerm2 側でキー→バイト列送信のマッピング(`⌃⌘[`→`^T [` 等)、色・フォントのプロファイル定義、
それをファイルとして配布・インストールする仕組み(setup.sh の darwin 分岐)。

### 1.4 What is out of scope?

HackGen フォント自体のインストール、herdr のインストール、WT の `ctrl+shift`/`alt+shift`
別名チョードの再現(ユーザー確認済みで本命は ctrl+alt 系のみ)、iTerm2 のその他の環境設定
(グローバル preferences)の管理。

## 2. Assumptions & Constraints

### 2.1 What do we take as true?

herdr の config.toml は OS 共通(未検証だが XDG パスは共通)。iTerm2 はインストール済み。
HHKB では Windows の Alt 位置のキーが Mac では Cmd — よって Win の ctrl+alt 系は Mac では ⌃⌘ 系が
同じ指運びになる。iTerm2 は `⌃T` を既定で奪わない(⌘T が新タブ)ため、プレフィックスのパススルー
設定は不要。

### 2.2 What binds the solution?

iTerm2 は Windows Terminal のような単一の可搬な settings.json を持たず、設定は
`com.googlecode.iterm2.plist` に集約される。dotfiles で扱うにはファイル1個で完結し、
iTerm2 が起動中でも安全に読み込める仕組みが必要。既存の setup.sh の構造
(`backup_then_copy` によるコピー方式、シンボリックリンクなし)を踏襲する。

## 3. Design overview

### 3.1 What is the core idea, and why does it solve the problem?

iTerm2 の **Dynamic Profiles** を使う。`~/Library/Application Support/iTerm2/DynamicProfiles/` に
置いた JSON をiTerm2 が自動で読み込み、プロファイルとして追加する。キーマッピング・色・フォントは
すべてプロファイル単位で定義できるため、必要な設定全部が JSON 1ファイルで完結し、既存の
setup.sh のコピー方式にそのまま乗る。

### 3.2 What are the pieces, and what is each responsible for?

- `iterm2/herdr.json` — Dynamic Profile 本体。Keyboard Map(4エントリ)、Gruvbox Dark の色、
  HackGen Console NF 13pt を持つ。
- `setup.sh` の darwin 分岐 — 上記 JSON を DynamicProfiles ディレクトリへ `backup_then_copy` で
  配置し、WT ブロックをスキップする。
- 既存の herdr ブロック — OS 共通でそのまま動く(`~/.config/herdr/` は mac でも同じ)。

### 3.3 How does work move?

`setup.sh` 実行 → OS 判定 → darwin なら herdr config + iTerm2 JSON を配置 → iTerm2 が
DynamicProfiles ディレクトリを監視していて自動反映(起動中でも再起動不要)→ ユーザーは
「herdr」プロファイルを選ぶ(必要ならデフォルト化は iTerm2 の UI から)。

## 4. Detailed design

### 4.1 What does the Keyboard Map guarantee, and how is a breach caught?

保証: `⌃⌘[`/`⌃⌘]`/`⌃⌘U` が herdr のプレフィックス列(0x14 + 文字)、`⇧Enter` が `\n` を送信する。
エントリは iTerm2 の `0x<keycode>-0x<modifier flags>` 形式で、アクションは Send Escape Sequence /
Send Text。破れの検出: 作成時にキーコード・修飾フラグを手計算と照合(タスク#1の静的検証)、
最終的にはユーザーの実機確認(タスク#3)。macOS/iTerm2 既定との衝突は ⌃⌘ 系・⇧Enter とも既知の
割り当てがないことを確認済み(⌃⌘F フルスクリーンとは衝突しない)。

### 4.2 What does the Dynamic Profile guarantee, and how is a breach caught?

保証: JSON が valid で Guid/Name を持てば iTerm2 が自動でプロファイル登録し、再コピー時も
Guid 固定なので同一プロファイルが更新される(重複しない)。破れの検出: JSON 構文エラー時は
iTerm2 が読み込み失敗を通知しプロファイルが現れない — タスク#1 の `json.tool` 検証と
タスク#2 の配置確認で事前に捕捉する。

### 4.3 What does the setup.sh darwin branch guarantee, and how is a breach caught?

保証: darwin では WT ブロック(`wslpath`/`cmd.exe` 依存)に到達せず、非 darwin では従来動作が
バイト単位で保たれる。破れの検出: mac での実行テスト(exit 0 + 配置確認)と、WSL 経路のロジックに
差分がないことのレビュー(タスク#2)。

## 5. Alternatives considered

### 5.1 Why this shape, and not another?

- **「Load preferences from custom folder」+ plist 全体を dotfiles 管理**: iTerm2 の全設定を
  奪ってしまい、plist はバイナリ化・頻繁な書き戻しで diff が汚れる。今回必要なのは1プロファイル分
  だけなので過剰。
- **`defaults write` の羅列を setup.sh に書く**: Keyboard Map のような入れ子 dict の記述が
  非常に壊れやすく、iTerm2 起動中の書き込みは上書きされ得る。
- **Karabiner-Elements でキー変換**: 端末外のグローバル常駐が増え、iTerm2 以外にも効いてしまう。
  端末内で完結する Dynamic Profiles が最小。

### 5.2 What did we trade away?

デフォルトプロファイル化は自動でできない(Dynamic Profile を既定にするにはユーザーが iTerm2 UI で
一度設定する必要がある)。またグローバル設定(ウィンドウ挙動等)は管理対象外のまま。いずれも
初回1回の手作業として受容する。
