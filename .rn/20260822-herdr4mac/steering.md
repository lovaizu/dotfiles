Rn version: 0.8.0
Design: .rn/20260822-herdr4mac/design.md

# Goal

この dotfiles の目的は、Win(WSL + Windows Terminal)と Mac(iTerm2)の端末環境を
「clone → setup 一発」で再現し、毎回手で設定しなくて済むようにすること。そのために両OSの設定を
同じ使い勝手に統一して管理する — テーマ(Gruvbox Dark)、フォント(HackGen Console NF 13)、
herdr 操作(prefix `^T`)、プレフィックスなしの即時切替(Win: `ctrl+alt+{[,],u}` / Mac:
`⌃⌘{[,],U}` — HHKB では Alt と Cmd が同じ物理位置)、`⇧Enter` での改行送信。

本セッションでは Mac(iTerm2)対応を新規追加し、あわせて Win 側の設定内容を見直して統一仕様に
揃え、setup.sh を共通部+OS別の構成に再編する。統一仕様は README に明文化する。

さらに同じ考え方を Claude Code のユーザー設定にも広げる: `~/.claude/settings.json` と
ステータスライン用シェルスクリプトを dotfiles に取り込み、両OSで setup.sh から再現できるようにする。

# Acceptance criteria

- README に統一仕様が明文化されている: 操作×OS別キーの対応表(即時切替3操作・⇧Enter・プレフィックス
  パススルー)、テーマ・フォント、セットアップ手順(Win / Mac 双方)
- iTerm2 用設定が dotfiles に存在し、インストールした iTerm2 で:
  - `⌃⌘[` が `0x14 0x5b`(`^T [`)、`⌃⌘]` が `0x14 0x5d`(`^T ]`)、`⌃⌘U` が `0x14 0x75`(`^T u`)を送信する
  - `⇧Enter` が `\n`(0x0a)を送信する
  - `⌃T` は横取りされず端末(herdr)に届く
  - カラースキームは Gruvbox Dark、フォントは HackGen Console NF 13pt
- windows-terminal/settings.json が統一仕様に整理されている: 即時切替は `ctrl+alt` 系のみ
  (`ctrl+shift` / `alt+shift` の別名チョードは削除)、`⇧Enter`→`\n`・`ctrl+t` 無効化・外観・
  プロファイル定義は維持
- `setup.sh` が共通部(herdr config)+OS別(darwin: iTerm2 Dynamic Profile 配置と、Homebrew が
  あれば HackGen フォントのインストール / WSL: WT settings.json 配置)の構成で、両OSで exit 0 で
  完了する(darwin では `wslpath`/`cmd.exe` 不在で落ちない、WSL では従来と同等の配置結果)
- herdr/config.toml は OS 共通のまま(OS 別の分岐を持ち込まない)。`[keys]` は変更しない。
  `[theme]` は端末側テーマ(Gruvbox Dark)と揃える — herdr の UI テーマが `gruvbox`(dark)であること
- `claude/settings.json` が dotfiles にあり、ホーム依存の絶対パス(statusLine / hooks の command)が
  `"$HOME/..."`(ダブルクォート囲み)で書かれていて、mac(`/Users/...`)と WSL(`/home/...`)の双方で
  正しい実パスに解決される。リテラルのホームパスを含まない
- `claude/settings.json` に `remoteControlAtStartup: false` が含まれる(キー名は Claude Code の
  設定スキーマで確認済み)。既存の設定値(outputStyle / effortLevel / theme / tui / enabledPlugins /
  extraKnownMarketplaces / statusLine / SessionStart フック / skipDangerousModePermissionPrompt /
  agentPushNotifEnabled)は現行の `~/.claude/settings.json` と同じ内容が保たれる
- `claude/scripts/statusline.sh` が dotfiles にあり、配置後のステータスラインが従来と同じ
  `C:…k/…k 5h:…% 7d:…% | モデル/努力度 | ディレクトリ@ブランチ` 形式で表示される
- `settings.json` が参照するカスタムテーマの実体(`claude/themes/catppuccin-mocha.json`、および
  対になる `catppuccin-latte.json`)が dotfiles にあり、配置される。他PCでテーマ名だけが残って
  組み込み dark に無警告フォールバックする状態にならない
- `setup.sh` の共通部が両OSで `~/.claude/settings.json`・`~/.claude/scripts/statusline.sh`・
  `~/.claude/themes/*.json` を配置し、既存ファイルは BACKUP_DIR に退避される。配置後の
  settings.json が有効な JSON である
- `setup.sh` が `jq` 不在を検出して警告する(statusline.sh は jq が無いと exit 0 のまま
  ` |  | dir@branch` と壊れた表示になり、無言で失敗するため)
- setup.sh の配置方式が2種類に分かれている: dotfiles でしか生成しないファイル
  (`iterm2/herdr.json` / `claude/scripts/statusline.sh` / `claude/themes/*.json`)は丸ごと上書き、
  アプリ側も書くファイル(`~/.claude/settings.json` / `~/.config/herdr/config.toml` /
  WT の `settings.json`)は **項目マージ** — dotfiles が持つキーは置き換え、dotfiles に無いキーは
  配置先のものを残す
- 項目マージによって、配置先にしか存在しない設定(そのマシンで `/config` や herdr UI から変えた値、
  WT がそのマシンの WSL ディストロ向けに生成したプロファイル)が失われない
- WT の `profiles.list` は `guid` をキーに1件ずつ突き合わせてマージされ、dotfiles に無い
  プロファイルが配置先に残る
- マージ処理が `jq` と `tomllib` のどちらにも依存しない(mac の python3 は 3.9 系で `tomllib` が無く、
  WSL 既定に `jq` が無いため)
- README に Claude Code 設定の管理対象・herdr 統合の前提(`hooks/herdr-agent-state.sh` は herdr 側が
  導入するため dotfiles では管理しない)・セットアップ手順が記載されている。あわせて配布時に
  意識が要る3点が明記されている: `jq` が前提であること、`skipDangerousModePermissionPrompt: true`
  も配布されること、`rn@ccpm` はバージョン非固定で初回オンライン起動が要ること

# Assumptions

- herdr の `config.toml` は OS 共通で、mac でもそのまま `~/.config/herdr/config.toml` に置けば動く(未検証)
- iTerm2 はユーザーがインストール済み。mac のフォントは Homebrew(cask `font-hackgen-nerd`)が
  あれば setup.sh で入れ、なければスキップ(手動導入でも可)。Win 側のフォントインストールは
  WSL からは行えないため従来どおり手動(README に手順を記載)
- iTerm2 / WT の実機での鍵送信確認はユーザーが行う(エージェントは設定ファイルの静的検証まで)
- WT の `ctrl+shift` / `alt+shift` 別名チョードは削除してよい(本命は `ctrl+alt` 系 — ユーザー確認済み。
  削除自体の最終確認はプランゲートで取る)
- シェル自体は統一しない: Win は WT のプロファイル(PowerShell / WSL bash)、Mac は zsh のまま。
  herdr の起動は両OSとも手動
- `~/.claude/hooks/herdr-agent-state.sh` は herdr の統合インストーラが生成・上書きするファイル
  (ファイル冒頭に "managed by herdr" と明記)なので dotfiles では管理しない。settings.json の
  SessionStart エントリだけを持ち、スクリプト本体は herdr の導入に委ねる
- settings.json の `command` はシェル経由で実行されるため `$HOME` は展開される — 検証済み(Claude Code
  2.1.241 のバイナリ内、hook `command` スキーマの説明に "When absent [args], `command` runs through a
  shell (bash on POSIX, PowerShell on Windows without Git Bash)" とあり、statusLine も同じランナー
  `Oes(i,"StatusLine","statusLine",…)` を通る)。よってプレースホルダ置換は行わず `$HOME` を直接書く。
  ホームパスに空白が含まれても壊れないよう、両 command のパスはダブルクォートで囲む
- `~/.claude/settings.json` は Claude Code 自身が(/config 等で)書き換えることがある。配置は
  バックアップのうえ**項目マージ**とし(dotfiles が持つキーは dotfiles の値で置き換え、dotfiles に
  無いキーは配置先のものを残す)、手元で変えた設定を dotfiles に戻すのはユーザーの運用とする。
  マージには削除の概念がないため、dotfiles 側でキーを消しても配置先からは消えない
- `~/.claude/output-styles/sleek.md` は現行 settings.json が参照していない(`outputStyle` は組み込みの
  `Concise`)ため、再現に必要な最小セットから外す — ユーザー確認済み
- `remoteControlAtStartup` を明示 `false` にするのは原本の複製ではなく挙動変更。未設定時の実効値は
  組織デフォルト次第で必ずしも false ではないため、配置後に `/config` 上の表示で確認する
- `~/.config/herdr/config.toml` は herdr が実行時に書き戻す — 実証済み(8/24 09:05 に setup.sh が
  repo 版 363 B `name = "gruvbox"` を配置したのち、09:57 時点で 369 B `name = "gruvbox-light"` に
  変化)。`onboarding = false` の存在と `herdr config reset-keys` の存在も herdr 側が所有者であることを示す
- WT の `settings.json` も WT 自身が書く。`profiles.list` にはそのマシンの WSL ディストロ由来の
  GUID(Ubuntu / ClaudeCode / my)が入るため、丸ごと配ると別マシンで実ディストロ定義を壊す
- mac の python3 は 3.9.6 で `tomllib`(3.11+)が無い。TOML のマージは行ベースのキー置換で行う —
  副産物としてコメントと行順が保たれる。JSON は python3 標準の `json` でマージする

# Rules

- commit and push every change; one completion marker per task
- 会話・ドキュメントは日本語(コード・コミットメッセージは英語)
- herdr/config.toml の `[keys]` には手を入れない(`[theme]` は端末側と揃えるため変更可)

# Tasks

### #1: README に統一仕様を定義する

**Purpose**: 両OSで揃える使い勝手(キー対応表・テーマ・フォント)とセットアップ手順を README に
明文化し、以降のタスクの仕様源にする。

**Prerequisites**: none

**Steps**:

- [x] README.md に記載: リポジトリの目的、操作×キー対応表(操作 / herdr 列 / Win キー / Mac キー)、テーマ・フォント、セットアップ手順(WSL: `./setup.sh`、mac: `./setup.sh`、Win フォントは手動)
- [x] self-check (OK/NG per completion criterion, record in checks/1.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- README に対応表があり、即時切替3操作(previous/next workspace, next agent)・⇧Enter・⌃T
  パススルーについて Win / Mac 双方のキーと送信内容(herdr 列)が読み取れる
- テーマ(Gruvbox Dark)・フォント(HackGen Console NF 13)と、両OSのセットアップ手順
  (フォントの入手方法含む)が記載されている
- 記載内容が steering の Acceptance criteria の対応表と矛盾しない

### #2: iTerm2 Dynamic Profile を作成する

**Purpose**: 統一仕様どおりのキーマッピング・Gruvbox Dark・HackGen フォントを含む iTerm2
Dynamic Profile JSON を `iterm2/herdr.json` として追加する。

**Prerequisites**: #1

**Steps**:

- [x] `iterm2/herdr.json` を作成: Guid 固定の Dynamic Profile。Keyboard Map に `⌃⌘[` → `0x14 [`、`⌃⌘]` → `0x14 ]`、`⌃⌘U` → `0x14 u`、`⇧Enter` → `\n` の Send-Text エントリ、Gruvbox Dark の Ansi 0–15 / Foreground / Background / Cursor / Selection 色、`Normal Font: HackGenConsoleNF-Regular 13` を定義
- [x] JSON の構文と必須キー(Guid / Name / Keyboard Map のキーコード・修飾フラグ表記)を静的検証(`python3 -m json.tool` + キーコードの手計算照合)
- [x] self-check (OK/NG per completion criterion, record in checks/2.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- `iterm2/herdr.json` が有効な JSON で、iTerm2 の Dynamic Profile 仕様の必須キー(Guid, Name)を持つ
- Keyboard Map に4エントリが存在し、キーコード(修飾フラグ含む)と送信バイト列が README の対応表
  (⌃⌘[→`^T [`, ⌃⌘]→`^T ]`, ⌃⌘U→`^T u`, ⇧Enter→`\n`)と一致する
- 色定義が windows-terminal/settings.json の Gruvbox Dark スキームの16色+前景/背景と同一の値である

### #3: Windows Terminal 設定を統一仕様に整理する

**Purpose**: windows-terminal/settings.json から別名チョード(`ctrl+shift` / `alt+shift` 系)を
削除し、即時切替を `ctrl+alt` 系のみに統一する。

**Prerequisites**: #1

**Steps**:

- [x] settings.json の keybindings から `ctrl+shift+[/]/u`・`alt+shift+[/]/u` のエントリを削除(sendInput アクション定義・`ctrl+alt` 系・⇧Enter・`ctrl+t` 無効化・その他 WT 固有キーと外観・プロファイルは維持)
- [x] JSON 構文検証と、残存キーバインドが README の対応表と一致することの照合
- [x] self-check (OK/NG per completion criterion, record in checks/3.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- settings.json が有効な JSON で、即時切替の keybinding が `ctrl+alt+[/]/u` の3つのみになっている
- `⇧Enter`→`\n`、`ctrl+t` 無効化、`ctrl+c/v`・`ctrl+shift+f`・`alt+shift+d`、外観(Gruvbox Dark /
  HackGen 13)、プロファイル定義に変更がない
- 未使用になった action 定義が残っていない

### #4: setup.sh を共通部+OS別構成に再編する

**Purpose**: OS 判定を導入し、共通部(herdr)のあと darwin では iTerm2 設定配置+フォント
(Homebrew があれば)、WSL では従来の WT 配置を行うようにする。

**Prerequisites**: #2, #3

**Steps**:

- [x] `setup.sh` を再編: 共通部(herdr config 配置)→ `uname` による OS 判定 → darwin: `iterm2/herdr.json` を `~/Library/Application Support/iTerm2/DynamicProfiles/` に `backup_then_copy`、`brew` があれば `font-hackgen-nerd` をインストール(なければメッセージを出してスキップ)/ それ以外(WSL): 従来の WT ブロック
- [x] mac 上で `setup.sh` を実行し、exit 0 で herdr config と Dynamic Profile が配置されること(brew 有無の両分岐のメッセージ)を確認
- [x] `bash -n`(+ shellcheck があれば)で構文検証。WSL 経路が従来と同等の配置を行うことをコードレビューで確認
- [x] self-check (OK/NG per completion criterion, record in checks/4.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- mac 上で `setup.sh` が exit 0 で完了し、`~/Library/Application Support/iTerm2/DynamicProfiles/herdr.json` と `~/.config/herdr/config.toml` が配置されている
- darwin では `wslpath` / `cmd.exe` 不在でもエラー終了せず、WT ブロックに到達しない
- WSL 経路は従来と同じファイルを同じ場所に配置する(herdr config + WT settings.json)
- Homebrew 不在の mac でもエラー終了しない

### #5: Evaluation sign-off

**Purpose**: Acceptance criteria の充足をユーザーに提示し、承認を得る。

**Prerequisites**: #1, #2, #3, #4, #6, #7, #8, #9, #10, #11, #12

**Steps**:

- [x] Acceptance criteria を1件ずつ検証した結果(README・両設定ファイルの対応表照合・setup.sh 実行結果)を提示する
- [x] ユーザーの実機確認を依頼する: mac は iTerm2 で ⌃⌘[/⌃⌘]/⌃⌘U/⇧Enter/⌃T(実施済み: raw モード捕捉で `14 5b 14 5d 14 75 0a 14` — 全キー期待どおり)、Win は次回同期時に WT で ctrl+alt 系
- [x] 評価中に判明した不具合に対応する(revise 1 巡目):
      (a) herdr プロファイルが iTerm2 のデフォルトでないとキーが効かない → setup.sh に検出警告、README に手順明記
      (b) `.bak` が DynamicProfiles 内に残り同一 Guid の二重プロファイルになる → バックアップ先を `~/.local/state/dotfiles-backups/` に変更
      (c) herdr の UI テーマが `gruvbox-light` で端末の Gruvbox Dark と不一致 → `gruvbox` に変更(steering の Rules / Acceptance criteria も更新)
- [x] ユーザーが新規ウィンドウ(⌘N)で確認: ワークスペース切り替えが効くこと、herdr UI が暗い配色になること(実施済み: 動作確認 OK)
- [ ] revise 2 巡目: Claude Code 設定(settings.json / statusline.sh)の dotfiles 化 — #6〜#8 として追加、完了後に再提示
- [ ] verdict を /rn:ty(approve)または /rn:gm(revise → 対応して再提示)で受ける

**Completion criteria**:

- Acceptance criteria の全項目に OK/NG と根拠が提示され、ユーザーが /rn:ty で承認している

### #6: Claude Code 設定ファイルを dotfiles に取り込む

**Purpose**: `~/.claude/` 配下のうち再現に必要なファイル(settings.json / statusline.sh /
カスタムテーマ)を `claude/` 配下にホーム非依存の形で複製し、両OSから同じ設定を再現できる
元データにする。

**Prerequisites**: none

**Steps**:

- [x] `claude/settings.json` を作成: 現行 `~/.claude/settings.json` の内容を写し、`remoteControlAtStartup: false` を追加
- [x] `claude/scripts/statusline.sh` を作成: 現行 `~/.claude/scripts/statusline.sh` をそのまま複製(ホーム依存の記述がないことを確認)
- [x] `statusLine.command` と SessionStart フックの `command` 内のホームパスを `"$HOME/..."`(ダブルクォート囲み)に書き換える。プレースホルダ方式は採らない — `command` がシェル経由で実行されることを検証済みのため
- [x] `claude/themes/catppuccin-mocha.json` と `claude/themes/catppuccin-latte.json` を現行 `~/.claude/themes/` から複製(`theme: "custom:catppuccin-mocha"` の実体。無いと他PCで無警告フォールバックする)
- [x] `python3 -m json.tool` で全 JSON の構文検証、`sh -n` と `dash -n` で statusline.sh の構文検証、原本との diff で意図した差分のみであることを照合
- [x] self-check (OK/NG per completion criterion, record in checks/6.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)
- [x] 修正ラウンド後の再レビュー(QA / Craft / Verification)

**Completion criteria**:

- `claude/settings.json` が有効な JSON で、リテラルのホームパス(`/Users/…` / `/home/…`)を含まず、
  2つの `command` がどちらも `"$HOME/…"` をダブルクォートで囲んでいる
- 現行 `~/.claude/settings.json` との差分が「2箇所の command のパスの `$HOME` 化(クォート付与を含む)」と
  「`remoteControlAtStartup: false` の追加」のみで、他のキー・値が変わっていない
- `claude/scripts/statusline.sh` が `sh -n` / `dash -n` を通り、現行の
  `~/.claude/scripts/statusline.sh` とバイト一致する
- `claude/themes/catppuccin-mocha.json` と `claude/themes/catppuccin-latte.json` が有効な JSON で、
  現行 `~/.claude/themes/` の同名ファイルとバイト一致する
- 秘密情報(APIキー・トークン等)が含まれていない

### #7: setup.sh 共通部で Claude Code 設定を配置する

**Purpose**: setup.sh の共通部に Claude Code 設定の配置を追加し、両OSで `~/.claude/` 以下に
settings.json・statusline.sh・カスタムテーマが置かれるようにする。

**Prerequisites**: #6, #9

**Steps**:

- [ ] `setup.sh` の共通部(OS 判定より前)に Claude Code ブロックを追加: `~/.claude/scripts/` と `~/.claude/themes/` を作成し、`claude/scripts/statusline.sh`(実行権付与)と `claude/themes/*.json` は `backup_then_copy` で上書き配置、`claude/settings.json` は #9 の JSON マージヘルパーで項目マージ
- [ ] `~/.claude/hooks/herdr-agent-state.sh` が無い場合に警告を出す(herdr 統合が未導入だと SessionStart フックが空振りするため)
- [ ] `command -v jq` を確認し、不在なら警告を出す(mac は `brew install jq`、Ubuntu/WSL は `sudo apt install jq`)。既存の herdr 不在警告と同じ書式に揃える
- [ ] mac 上で実行し exit 0、配置された settings.json が有効な JSON であること、statusline.sh が実行可能なこと、themes が配置されたことを確認。`bash -n`(+ shellcheck があれば)で構文検証
- [ ] Claude Code 上で `/config` を開き、"Enable Remote Control for all sessions" が `false` になっていることを目視確認する(`remoteControlAtStartup` は原本に無い追加設定で、未設定時の実効値が false とは限らないため)
- [ ] self-check (OK/NG per completion criterion, record in checks/7.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- mac 上で `setup.sh` が exit 0 で完了し、`~/.claude/settings.json`・
  `~/.claude/scripts/statusline.sh`(実行権あり)・`~/.claude/themes/catppuccin-{mocha,latte}.json`
  が配置されている
- 配置された settings.json に dotfiles 側の全キーが反映され、かつ配置前に存在した
  dotfiles 外のキー・値がそのまま残っている
- ホームパスに空白が含まれる環境でも `command` が壊れない — 配置後の `command` 文字列内の
  `$HOME` がダブルクォートで囲まれている
- 既存の `~/.claude/settings.json` は上書き前に BACKUP_DIR に退避されている
- Claude Code ブロックが OS 判定より前(共通部)にあり、WSL 経路でも同じ配置が行われる。既存の
  herdr / iTerm2 / WT の配置動作は変わらない
- `jq` 不在時と herdr 統合フック不在時に、それぞれ警告が出てエラー終了しない

### #8: README に Claude Code 設定の管理範囲と手順を追記する

**Purpose**: dotfiles が管理する Claude Code 設定の範囲・herdr 統合との境界・配置方式(上書き /
項目マージ)・セットアップ後の確認方法を README に明文化する。

**Prerequisites**: #6, #7, #9, #10

**Steps**:

- [ ] README.md に節を追加: 管理対象(`claude/settings.json` / `claude/scripts/statusline.sh` / `claude/themes/*.json`)と配置先、`claude/` 以下は `~/.claude/` の構造をそのまま写す規則、`hooks/herdr-agent-state.sh` は herdr 側が導入する旨、`./setup.sh` 後に Claude Code を再起動して反映する旨
- [ ] 配布時に意識が要る3点を明記: `jq` が前提(不在だとステータスラインが無言で壊れる)、`skipDangerousModePermissionPrompt: true` も配布されること、`rn@ccpm` はバージョン非固定で初回オンライン起動が要ること
- [ ] 配置方式の表を追加: どのファイルが「丸ごと上書き」でどれが「項目マージ」か、その理由(そのファイルをアプリ側も書くかどうか)
- [ ] 項目マージでも dotfiles にあるキーは dotfiles 側の値で置き換わるため、手元での `/config`・herdr UI での変更を残したい場合は dotfiles 側にも反映する必要がある旨を明記
- [ ] 記載内容が steering の Acceptance criteria および実際の setup.sh の挙動と一致することを照合
- [ ] self-check (OK/NG per completion criterion, record in checks/8.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- README を読んだ第三者が、dotfiles が管理する Claude Code 設定ファイルと配置先、および
  管理しないもの(herdr 統合フックの本体、output-styles)を区別できる
- `jq` 前提・`skipDangerousModePermissionPrompt` の配布・`rn@ccpm` のバージョン非固定・
  `/config` 変更の手戻し運用の4点が記載されている
- 記載された手順が実際の setup.sh の挙動と一致し、README 内の既存記述(端末統一仕様)と矛盾しない


### #9: setup.sh に項目マージのヘルパーを実装する

**Purpose**: アプリ側も書く設定ファイルに対して「dotfiles が持つキーだけを置き換え、dotfiles に
無いキーは配置先のものを残す」マージを、`jq` にも `tomllib` にも依存せず行えるようにする。

**Prerequisites**: none

**Steps**:

- [x] `setup.sh` に `merge_json` を実装: python3 標準の `json` で配置先と dotfiles を読み、再帰的な dict マージ(dotfiles 優先、配列は葉として扱う)を行って書き戻す。配置先が無い/壊れている場合は dotfiles 側をそのまま書く。書き込み前に BACKUP_DIR へ退避
- [x] `merge_json` に `profiles.list` 用の特例を実装: 配列内オブジェクトを `guid` をキーに突き合わせ、dotfiles にある guid は置き換え、無い guid は配置先のものを残す
- [x] `setup.sh` に `merge_toml` を実装: 行ベースで `[section]` を追跡しつつ `key = value` を突き合わせ、dotfiles にあるキーは値を置き換え、無いキーは配置先の行(コメント・空行・順序を含む)をそのまま残す。dotfiles にしか無いキーは該当セクションの末尾に追加し、セクション自体が無ければセクションごと追加
- [x] 一時ファイルに書いてから `mv` する(書き込み中の中断で設定ファイルを壊さないため)
- [x] ユニット的な検証: スクラッチに作った擬似 JSON / TOML に対して、置換・保持・追加・セクション追加・配置先が空/不正の各ケースを実行して結果を確認する
- [x] `bash -n`(+ shellcheck があれば)で構文検証
- [x] self-check (OK/NG per completion criterion, record in checks/9.md)
- [x] QA expert review (subagent)
- [x] Design expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)
- [ ] 未解決の Valid 指摘 10 件(`checks/9.md` 末尾)の扱いをユーザーと決めて反映する — 修正 3 巡の上限に達したため escalate 済み

**Completion criteria**:

- `merge_json` が、配置先にしか無いキーを保持したまま dotfiles 側のキーを反映し、結果が有効な
  JSON である。ネストしたオブジェクト(`hooks` / `profiles.defaults` など)でも同様に動く
- `merge_json` が `profiles.list` を `guid` 単位で突き合わせ、dotfiles に無い guid のプロファイルを
  残す
- `merge_toml` が、配置先にしか無いキー・コメント・行順を保ったまま dotfiles 側のキーを反映し、
  結果が herdr に読める TOML である(`herdr config check` が通る)
- 配置先ファイルが存在しない場合と、内容が壊れている場合のどちらでもエラー終了せず、dotfiles 側の
  内容で復旧する
- マージ処理が `jq` / `tomllib` / その他の外部依存を必要とせず、mac の python3 3.9 と
  Ubuntu の python3 の双方で動く
- 書き込みが原子的で、途中で中断しても配置先が半端な内容にならない

### #10: herdr と Windows Terminal の配置を項目マージに切り替える

**Purpose**: 既に丸ごと上書きで配置している `~/.config/herdr/config.toml` と WT の
`settings.json` を #9 のヘルパー経由に切り替え、配置先固有の設定が消えないようにする。

**Prerequisites**: #9

**Steps**:

- [ ] `setup.sh` の herdr ブロックを `merge_toml` 経由に切り替える
- [ ] `setup.sh` の WT ブロックを `merge_json` 経由に切り替える(`profiles.list` 特例つき)
- [ ] mac 上で実行し、`~/.config/herdr/config.toml` の dotfiles 由来のキーが反映され、herdr が書き込んだ dotfiles 外のキーが残ることを確認。`herdr config check` が通ることも確認
- [ ] WT 経路は mac で実行できないため、擬似的な配置先ファイル(別マシンを模して WSL ディストロが異なるもの)を作ってマージ結果をコードレビューで確認する。実機確認は次回 Windows 同期時
- [ ] herdr の `[theme] name` が dotfiles の値どおりに反映されることを確認する(8/24 時点で配置先が `gruvbox-light` に書き戻されており、#5 の revise (c) が効いていない状態)
- [ ] self-check (OK/NG per completion criterion, record in checks/10.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- mac 上で `setup.sh` が exit 0 で完了し、`~/.config/herdr/config.toml` が dotfiles のキーを反映
  しつつ dotfiles 外のキーを保っている。`herdr config check` が通る
- 擬似的な WT 配置先(dotfiles に無い WSL ディストロのプロファイルを含むもの)に対してマージした
  結果に、そのプロファイルが残っている
- 既存の iTerm2 / statusline.sh / themes の配置は従来どおり丸ごと上書きのままである
- setup.sh が両OSで exit 0 のまま(WSL 経路は静的レビューまで)


### #11: iTerm2 プロファイルの色定義の欠落を塞ぐ

**Purpose**: `iterm2/herdr.json` が定義していない色キーが iTerm2 の Default プロファイル
(Catppuccin Latte)から引き継がれ、Gruvbox Dark の背景に対して読めない色になる問題を塞ぐ。
#2 の欠陥。完了基準が ANSI 16 色 + 前景/背景/カーソル/選択に限られていたため素通りした。

**Prerequisites**: #2

**Steps**:

- [x] `iterm2/herdr.json` に `Bold Color`(`#ebdbb2`)・`Cursor Text Color`(`#282828`)・`Badge Color`(`#fb4934`)を追加(`c978b22`)
- [x] 配置して実機で太字が読めることをユーザーが確認(実施済み)
- [ ] #2 の完了基準を「Default プロファイルから引き継ぐ色を残さない」旨に更新するかをユーザーと決める
- [ ] 残りの未定義キー(`Link Color` / `Selected Text Color` / `Cursor Guide Color` / `Match Background Color` ほか)を洗い、実際の描画先に対するコントラストで要否を判断する
- [ ] self-check (OK/NG per completion criterion, record in checks/11.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- `iterm2/herdr.json` が、iTerm2 の Default プロファイルから引き継ぐと Gruvbox Dark 上で
  読めなくなる色キーをすべて自前で定義している
- 各色が実際に描画される組み合わせ(太字は背景に、カーソル文字はカーソル色に、選択文字は
  選択背景に)で 4.5:1 以上のコントラストを持つ
- README の統一仕様と矛盾しない

### #12: herdr の UI テーマを light 前提に合わせる

**Purpose**: herdr の UI テーマはワークスペースの選択が判別できるようユーザーが意図的に
light にしている(Win でも同じ設定で読める)。dotfiles 側が `gruvbox`(dark)を持っているため
setup のたびに巻き戻る状態を解消する。

**Prerequisites**: none

**Steps**:

- [ ] `herdr/config.toml` の `[theme] name` を `gruvbox-light` にする
- [ ] steering の Acceptance criteria の「herdr の UI テーマが `gruvbox`(dark)であること」を
      light 前提に改める(#5 の revise (c) の判断を差し戻すことになるため、評価ゲートで承認を取る)
- [ ] README の記載を合わせる
- [ ] self-check (OK/NG per completion criterion, record in checks/12.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- `herdr/config.toml` の `[theme] name` が `gruvbox-light` で、setup 実行後も配置先が
  light のまま保たれる
- steering の Acceptance criteria と README が light 前提で一貫している


# State

(written by /rn:dn, read and reset to this placeholder by /rn:up. `Status` is `paused` while a
session is suspended — the signal /rn:up and /rn:dn search for — and resets to `not suspended` here,
so only a genuinely suspended session reads `paused`.)

- **Status**: paused
- **Date**: 2026-08-26
- **Last completed**: #1-#4 / #6。#9 は実装 + 修正 3 巡 + 各巡 4 軸レビューまで完了したが未チェックオフ
- **Next**: #9 — 未解決の Valid 指摘 10 件の扱いをユーザーと決めて反映する。あわせて持ち越しの判断 3 件に答えをもらう
- **Notes**: branch `worktree-herdr4mac` / PR https://github.com/lovaizu/dotfiles/pull/8(draft)。
  **#9 は修正 3 巡の上限に達し escalate 済み** — 未解決 10 件の全文は `checks/9.md` 末尾。データを
  失う方向の欠陥はゼロ(ファズ 26,082 件で違反 0)。coordinator の推奨は「値検査層を落として
  キー構造だけ保証する」に縮める案で、残存欠陥の多くがその層自体から出ているため。
  **未回答の判断 3 件**: (a) `hooks.<Event>` 配列と WT の `actions` / `schemes` を要素単位マージの
  対象にするか(#7 の完了基準に影響)、(b) 埋め込み python を `lib/merge.py` に切り出すか、
  (c) #10 で #4 の setup.sh を書き換えることの承認。herdr テーマの件は解決し #12 として起票。
  **要確認**: `~/.claude/settings.json` の `theme` が `"light"` に変わっている(8/24 は
  `custom:catppuccin-mocha`)。意図的かどうか未確認。
  Win 側(ctrl+alt 系・WT マージ結果)は次回 Windows 同期時に未検証のまま。
