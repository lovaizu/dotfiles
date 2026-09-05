Rn version: 0.8.0
Design: .rn/20260822-herdr4mac/design.md

# Goal

この dotfiles の目的は、Win(WSL + Windows Terminal)と Mac(iTerm2)の端末環境を
「clone → setup 一発」で再現し、毎回手で設定しなくて済むようにすること。そのために両OSの設定を
同じ使い勝手に統一して管理する — テーマ(Gruvbox Dark)、フォント(HackGen Console NF 14)、
herdr 操作(prefix `^T`)、プレフィックスなしの即時切替(Win: `ctrl+alt+{[,],u}` / Mac:
`⌃⌘{[,],U}` — HHKB では Alt と Cmd が同じ物理位置)、`⇧Enter` での改行送信。

本セッションでは Mac(iTerm2)対応を新規追加し、あわせて Win 側の設定内容を見直して統一仕様に
揃え、setup.sh を共通部+OS別の構成に再編する。統一仕様は README に明文化する。

さらに同じ考え方を Claude Code のユーザー設定にも広げる: `~/.claude/settings.json` と
ステータスライン用シェルスクリプトを dotfiles に取り込み、両OSで setup.sh から再現できるようにする。

# Acceptance criteria

- README が**意図と規則だけ**を書いている: 何ができるか(即時切替3操作・⇧Enter・プレフィックス
  パススルー)、なぜそうなっているか(両OSで同じ指運び / 端末は暗くその上の UI は明るい)、
  セットアップ手順(Win / Mac 双方)と手作業が要る箇所。**具体的な設定値は書かない** —
  フォント名とサイズ・色の hex・テーマ名・送信バイト列はすべて設定ファイル側にしか置かない
  (2か所でメンテできないため。キー対応表の列は「操作 / Win キー / Mac キー」まで)
- iTerm2 用設定が dotfiles に存在し、インストールした iTerm2 で:
  - `⌃⌘[` が `0x14 0x5b`(`^T [`)、`⌃⌘]` が `0x14 0x5d`(`^T ]`)、`⌃⌘U` が `0x14 0x75`(`^T u`)を送信する
  - `⇧Enter` が `\n`(0x0a)を送信する
  - `⌃T` は横取りされず端末(herdr)に届く
  - カラースキームは Gruvbox Dark、フォントは HackGen Console NF 14pt
- windows-terminal/settings.json が統一仕様に整理されている: 即時切替は `ctrl+alt` 系のみ
  (`ctrl+shift` / `alt+shift` の別名チョードは削除)、`⇧Enter`→`\n`・`ctrl+t` 無効化・外観・
  プロファイル定義は維持
- `setup.sh` が共通部(herdr config)+OS別(darwin: iTerm2 Dynamic Profile 配置と、Homebrew が
  あれば HackGen フォントのインストール / WSL: WT settings.json 配置)の構成で、両OSで
  **配置に失敗しなければ** exit 0 で完了する(darwin では `wslpath`/`cmd.exe` 不在で落ちない、
  WSL では従来と同等の配置結果)。配置に失敗した run は警告を出して残りを続行し、最後に失敗を
  列挙して非0で終わる — #10 で失敗の扱いも1種類に揃えた
- herdr/config.toml は OS 共通のまま(OS 別の分岐を持ち込まない)。`[keys]` は変更しない。
  `[theme]` は herdr の UI テーマが `gruvbox-light` であること — 端末そのものは Gruvbox Dark で、
  herdr の UI だけ light にする(ワークスペースの選択状態を判別しやすくするためユーザーが意図した配色)
- `claude/settings.json` が dotfiles にあり、ホーム依存の絶対パス(statusLine / hooks の command)が
  `"$HOME/..."`(ダブルクォート囲み)で書かれていて、mac(`/Users/...`)と WSL(`/home/...`)の双方で
  正しい実パスに解決される。リテラルのホームパスを含まない
- `claude/settings.json` に `remoteControlAtStartup: false` が含まれる(キー名は Claude Code の
  設定スキーマで確認済み)。既存の設定値(outputStyle / effortLevel / theme / tui / enabledPlugins /
  extraKnownMarketplaces / statusLine / SessionStart フック / skipDangerousModePermissionPrompt /
  agentPushNotifEnabled)は現行の `~/.claude/settings.json` と同じ内容が保たれる
- `claude/scripts/statusline.sh` が dotfiles にあり、配置後のステータスラインが従来と同じ
  `C:…k/…k 5h:…% 7d:…% | モデル/努力度 | ディレクトリ@ブランチ` 形式で表示される
- `claude/settings.json` の `theme` が組み込みの `light` である。カスタムテーマの実体を
  dotfiles で抱えない(組み込みテーマなので他PCでの無警告フォールバックが起きない)
- `setup.sh` の共通部が両OSで `~/.claude/settings.json` と `~/.claude/scripts/statusline.sh` を
  丸ごと上書きで配置する。配置後の settings.json が有効な JSON である(Claude Code が書く他のもの —
  `sessions/` `projects/` `history.jsonl` `plugins/` など — はすべて別ファイルなので巻き込まない)
- `setup.sh` が `jq` 不在を検出して警告する(statusline.sh は jq が無いと exit 0 のまま
  ` |  | dir@branch` と壊れた表示になり、無言で失敗するため)
- **dotfiles が正**。setup.sh は管理対象のファイルをすべて丸ごと上書きする — 配置方式は1種類だけで、
  ファイルごとの例外を持たない。dotfiles が持つ設定がそのマシンの設定であり、dotfiles からキーを
  消せばマシンからも消える
- 項目マージの機構(`lib/merge.py` と、それを呼ぶ `setup.sh` の経路、`tests/` のマージ用スイートと
  ファザ)が repo に存在しない。アプリが書き戻した値(herdr のテーマ名・`onboarding`)は
  上書きで dotfiles の値に戻る。WT がそのマシン向けに生成する WSL プロファイルについては、
  WT 自身が作り直す**という仮定**に立つ — WSL 実機で未検証(design.md §4.7 の境界)
- 配置先が dotfiles の原本と違うとき、上書きの前に BACKUP_DIR へ退避する。載せ替えの初回だけでなく、
  アプリが設定を書き戻したあとの実行でも退避は起きる(herdr はテーマ名と `onboarding` を書き戻す)。
  世代管理も剪定もしないので BACKUP_DIR は増える — 不要になったらユーザーが消す。原本と同じ内容の
  配置先には何も書かず、退避も取らない
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
- `~/.claude/settings.json` は Claude Code 自身が(/config 等で)書き換えることがある。それでも
  配置は**バックアップのうえ丸ごと上書き**とする — dotfiles が正なので、手元で変えた設定は
  次の setup で dotfiles の値に戻る。残したい変更は dotfiles 側に入れるのがユーザーの運用
  (#10 で項目マージから改めた。判断の根拠は `f672480`)
- `~/.claude/output-styles/sleek.md` は現行 settings.json が参照していない(`outputStyle` は組み込みの
  `Concise`)ため、再現に必要な最小セットから外す — ユーザー確認済み
- `remoteControlAtStartup` を明示 `false` にするのは原本の複製ではなく挙動変更。未設定時の実効値は
  組織デフォルト次第で必ずしも false ではないため、配置後に `/config` 上の表示で確認する
- `~/.config/herdr/config.toml` は herdr が実行時に書き戻す — 実証済み(8/24 09:05 に setup.sh が
  repo 版 363 B `name = "gruvbox"` を配置したのち、09:57 時点で 369 B `name = "gruvbox-light"` に
  変化)。`onboarding = false` の存在と `herdr config reset-keys` の存在も herdr 側が所有者であることを示す
- WT の `settings.json` も WT 自身が書く。`profiles.list` にはそのマシンの WSL ディストロ由来の
  GUID が入るが、これは WT がそのマシンで生成し直す在庫情報なので丸ごと上書きして構わない、
  という判断で #10 を進めた。**この「WT が作り直す」は WSL 実機で未検証の仮定**であり、
  撤回判断を支える唯一の未検証事項として残る(検証は次回 Windows 同期時)
- **Windows マシンは1台**。`windows-terminal/settings.json` は `profiles.list` にそのマシンの
  WSL ディストロ由来の GUID を抱えたまま配布されるので、丸ごと上書きが成り立つのはこの前提の下だけ。
  2台目に配ると、そのマシンに無いディストロの GUID が持ち込まれ、固有の GUID は消える —
  項目マージが実際に解いていた問題はここに実在し、上書きはそれを前提で回避している
  (design.md §4.7 の境界。台数が増えた時点でこの判断はやり直しになる)

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
- テーマ(Gruvbox Dark)・フォント(HackGen Console NF 14)と、両OSのセットアップ手順
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
- 秘密情報(APIキー・トークン等)が含まれていない

### #7: setup.sh 共通部で Claude Code 設定を配置する

**Purpose**: setup.sh の共通部に Claude Code 設定の配置を追加し、両OSで `~/.claude/` 以下に
settings.json・statusline.sh が置かれるようにする。

**Prerequisites**: #6

**注記(2026-09-01, #10)**: 本タスクは当時の方針(項目マージ)で実施・完了した。#10 で配置方式を
丸ごと上書きに改めたため、下記のうちマージに触れる Step と Completion criteria は現行の実装を
表していない。現行の保証は #10 の Completion criteria を見ること。

**Steps**:

- [x] `setup.sh` の共通部(OS 判定より前)に Claude Code ブロックを追加: `~/.claude/scripts/` を作成し、`claude/scripts/statusline.sh` は実行権を付与して `backup_then_copy` で上書き配置、`claude/settings.json` は #9 の JSON マージヘルパーで項目マージ(#10 で `deploy` による丸ごと上書きに変更)
- [x] `~/.claude/hooks/herdr-agent-state.sh` が無い場合に警告を出す(herdr 統合が未導入だと SessionStart フックが空振りするため)
- [x] `command -v jq` を確認し、不在なら警告を出す(mac は `brew install jq`、Ubuntu/WSL は `sudo apt install jq`)。既存の herdr 不在警告と同じ書式に揃える
- [x] mac 上で実行し exit 0、配置された settings.json が有効な JSON であること、statusline.sh が実行可能なことを確認。`bash -n`(+ shellcheck があれば)で構文検証
- [x] Claude Code 上で `/config` を開き、"Enable Remote Control for all sessions" が `false` になっていることを目視確認する(`remoteControlAtStartup` は原本に無い追加設定で、未設定時の実効値が false とは限らないため)
- [x] self-check (OK/NG per completion criterion, record in checks/7.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)
- [x] レビュー2巡分の指摘に対応(`781b6fe` `fa4c719`)。内側 `hooks` 配列を要素単位マージにする判断は
      ユーザー承認済み(design.md §4.7 を改訂)— この判断は #10 のマージ撤去により無効

**Completion criteria**:

- mac 上で `setup.sh` が exit 0 で完了し、`~/.claude/settings.json` と
  `~/.claude/scripts/statusline.sh`(実行権あり)が配置されている
- 配置された settings.json が dotfiles の原本とバイト単位で一致する(#10 以前は「dotfiles 外の
  キーが残っていること」を求めていたが、丸ごと上書きへの変更で保証が入れ替わった)
- ホームパスに空白が含まれる環境でも `command` が壊れない — 配置後の `command` 文字列内の
  `$HOME` がダブルクォートで囲まれている
- 既存の `~/.claude/settings.json` は上書き前に BACKUP_DIR に退避されている
- Claude Code ブロックが OS 判定より前(共通部)にあり、WSL 経路でも同じ配置が行われる。既存の
  herdr / iTerm2 / WT の配置動作は変わらない
- `jq` 不在時と herdr 統合フック不在時に、それぞれ警告が出てエラー終了しない

### #8: README を意図だけの記述に書き直し、Claude Code の管理範囲を加える

**Purpose**: README が具体的な設定値を持っているため、値を変えるたびに2か所をメンテすることに
なっている(フォントサイズの変更で発覚)。README の担当を「何ができるか / なぜそうなっているか /
手でやるしかない箇所」に絞り、値は設定ファイル側にしか置かない。あわせて Claude Code 設定の
管理範囲と、配布時に意識が要る前提を書く。

**Prerequisites**: #10(配置方式が確定してから書く)

**Steps**:

- [ ] README から具体的な設定値を落とす: フォント名とサイズ、Gruvbox Dark の hex、`gruvbox-light` /
      `light` というテーマ名、キー対応表の送信バイト列(`0x14 0x5b` 等)。対応表の列は
      「操作 / Win キー / Mac キー」まで
- [ ] 残す意図を明示的に書く: 両OSで同じ指運びになる理由(HHKB の Alt と ⌘ が同じ物理位置)、
      `^T` が端末に横取りされず herdr に届くことが前提であること、テーマが3層あり
      「端末は暗く、その上の UI は明るい」のは意図した組み合わせであること(ワークスペースの
      選択状態を判別するため)
- [ ] 配置方式を1行で書く: dotfiles が正で、管理対象はすべて丸ごと上書き。手元で `/config` や
      herdr UI から変えた設定を残したいなら dotfiles 側に入れる
- [ ] Claude Code の管理対象(`claude/settings.json` / `claude/scripts/statusline.sh`)と配置先、
      `claude/` 以下は `~/.claude/` の構造をそのまま写す規則、`hooks/herdr-agent-state.sh` は
      herdr 側が導入する旨、`./setup.sh` 後に Claude Code を再起動して反映する旨
- [ ] 配布時に意識が要る3点: `jq` が前提(不在だとステータスラインが無言で壊れる)、
      `skipDangerousModePermissionPrompt: true` も配布されること、`rn@ccpm` はバージョン非固定で
      初回オンライン起動が要ること
- [ ] README から値を落とした結果と `design.md` の記述を突き合わせる: §3.2 は README を
      「テーマ・フォントの源」と書き、§4.1 は「送信バイト列・外観の単一の正が README にある」と
      書いているので、値が README から消えると食い違う。design.md 側を追随させる
- [ ] 記載内容が steering の Acceptance criteria および実際の setup.sh の挙動と一致することを照合
- [ ] self-check (OK/NG per completion criterion, record in checks/8.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- README に具体的な設定値が残っていない — フォント名・サイズ、色の hex、テーマ名、送信バイト列を
  grep して0件。設定値を知りたい読者が、どの設定ファイルを見ればよいか分かる
- README を読んだ第三者が、dotfiles が管理する Claude Code 設定ファイルと配置先、および
  管理しないもの(herdr 統合フックの本体、output-styles)を区別できる
- `jq` 前提・`skipDangerousModePermissionPrompt` の配布・`rn@ccpm` のバージョン非固定・
  「dotfiles が正なので手元の変更は dotfiles に入れる」の4点が記載されている
- 記載された手順が実際の setup.sh の挙動と一致し、README 内の既存記述と矛盾しない

### #9: setup.sh に項目マージのヘルパーを実装する — 撤回(2026-09-01)

**撤回理由**: dotfiles が正であり、すべて丸ごと上書きする方針にユーザーが決めた。項目マージが
守ろうとした「配置先にしか無い設定」は、マシンの在庫情報(WT の WSL プロファイル、WT が作り直す)か、
アプリの書き戻し(herdr のテーマ名、上書きで戻るのが望ましい挙動)で、守る価値が無かった。
成果物の撤去は #10。

**Purpose**: アプリ側も書く設定ファイルに対して「dotfiles が持つキーだけを置き換え、dotfiles に
無いキーは配置先のものを残す」マージを、`jq` にも `tomllib` にも依存せず行えるようにする。

**Prerequisites**: none

**Steps**:

- [x] `setup.sh` に `merge_json` を実装: python3 標準の `json` で配置先と dotfiles を読み、再帰的な dict マージ(dotfiles 優先、配列は葉として扱う)を行って書き戻す。配置先が無い/壊れている場合は dotfiles 側をそのまま書く。書き込み前に BACKUP_DIR へ退避
- [x] `merge_json` に id 単位の配列マージを実装: 配列内オブジェクトを id キーで突き合わせ、dotfiles にある id は置き換え、無い id は配置先のものを残す。対象は WT の `profiles.list`(`guid`)・`actions`(`id`)・`schemes`(`name`)と Claude Code の `hooks.<Event>`(`matcher`) — いずれもアプリ自身が要素を書き足す配列
- [x] `setup.sh` に `merge_toml` を実装: 行ベースで `[section]` を追跡しつつ `key = value` を突き合わせ、dotfiles にあるキーは値を置き換え、無いキーは配置先の行(コメント・空行・順序を含む)をそのまま残す。dotfiles にしか無いキーは該当セクションの末尾に追加し、セクション自体が無ければセクションごと追加
- [x] 一時ファイルに書いてから `mv` する(書き込み中の中断で設定ファイルを壊さないため)
- [x] ユニット的な検証: スクラッチに作った擬似 JSON / TOML に対して、置換・保持・追加・セクション追加・配置先が空/不正の各ケースを実行して結果を確認する
- [x] `bash -n`(+ shellcheck があれば)で構文検証
- [x] self-check (OK/NG per completion criterion, record in checks/9.md)
- [x] QA expert review (subagent)
- [x] Design expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)
- [x] 未解決の Valid 指摘 10 件(`checks/9.md` 末尾)の扱いを決めて反映する — 値検査層を撤去する方針で決着。U1/U3/U4 は層ごと解消、U2/U6/U7/U8/U9/U10 は個別修正、U5 は 11 形状の実測で再現せず。持ち越し 3 件も同時に決着(`checks/9.md`)

**Completion criteria**:

- `merge_json` が、配置先にしか無いキーを保持したまま dotfiles 側のキーを反映し、結果が有効な
  JSON である。ネストしたオブジェクト(`hooks` / `profiles.defaults` など)でも同様に動く
- `merge_json` が上記4つの配列を id 単位で突き合わせ、dotfiles に無い id の要素(他マシンの WSL
  プロファイル、その端末で足したキー割り当てや配色、`/config` で足したフック)を残す
- `merge_toml` が、配置先にしか無いキー・コメント・行順を保ったまま dotfiles 側のキーを反映し、
  有効だった配置先が有効な TOML のまま返る(`herdr config check` が通る。`XDG_CONFIG_HOME` で
  読み先を差し替えて検査する)
- 値の綴りは検査しない — 裸の語が真偽値・数値・日付かは見ずバイト列のまま運ぶ。元から不正だった
  配置先が「マージした」で返り不正なままであることは許容する。許容しないのは、有効だった配置先が
  無効になって返ること
- 配置先ファイルが存在しない場合と、**構造が**壊れている場合(終端しない文字列・閉じない括弧・
  キーやテーブルの二重定義・TOML が許さない制御文字)のどちらでもエラー終了せず、dotfiles 側の
  内容で復旧する。自前パーサが構造を追えないだけの場合(`[[array of tables]]`、深すぎるネスト)は
  配置先を一切書かずに続行する
- マージ処理が `jq` / `tomllib` / その他の外部依存を必要とせず、mac の python3 3.9 と
  Ubuntu の python3 の双方で動く
- 書き込みが原子的で、途中で中断しても配置先が半端な内容にならない

### #13: マージャを `lib/merge.py` に切り出し、テストをリポジトリに入れる — 撤回(2026-09-01)

**撤回理由**: #9 と同じ。切り出した `lib/merge.py` ごと撤去する(#10)。

**Purpose**: `setup.sh` は 1360 行あり、その 1100 行超が埋め込み python で、シェルとしても
python としても読めない。切り出して両方を読める形にする。あわせて #9 の根拠(回帰スイートと
ファズ)が scratchpad にしか無く repo から再現できない状態を解消する。

**Prerequisites**: #9

**Steps**:

- [x] ヒアドキュメントの中身を `lib/merge.py` に移し、`merge_config` は `python3 "$REPO/lib/merge.py" ...` を呼ぶ形にする。`$REPO` の解決は setup.sh 自身の位置から行う(`cd` されても壊れないこと)
- [x] `lib/merge.py` 単体が python 3.9 と 3.12 の双方で構文を通り、`python3 lib/merge.py` を引数なしで叩くと usage を返すことを確認
- [x] `tests/` に `suite.py` / `fuzzmut.py` / `fuzzrand.py` / `realdata.sh` / `h.py` を入れる(`h.py` の `MERGE` 既定を `lib/merge.py` に向け、`extract.sh` は不要になるので落とす)
- [x] `tests/README.md` に走らせ方(オラクルに 3.12 が要る旨、マージ本体は 3.9 に投げる旨、`realdata.sh` が実ファイルをコピーしか触らない旨)を書く
- [x] 切り出し前後で `suite.py` が同じ結果(`PASS=127 FAIL=0`)であることと、`realdata.sh` が同じ結末になることを確認
- [x] self-check (OK/NG per completion criterion, record in checks/13.md)
- [-] QA / Craft / Verification expert review — 撤回により不要(成果物ごと #10 で撤去する)

**Completion criteria**:

- `setup.sh` に埋め込み python が残っておらず、`lib/merge.py` が単体で読める python ファイルとして存在する
- `setup.sh` をどのディレクトリから起動しても `lib/merge.py` を見つける
- `tests/` から `suite.py` が repo だけで走り、`PASS=127 FAIL=0`
- 切り出しによる挙動の変化がない(`realdata.sh` の結末と `suite.py` の結果が切り出し前と一致)

### #10: 配置を丸ごと上書きに統一し、項目マージ機構を撤去する

**Purpose**: 「dotfiles が正」という原則に実装を合わせる。項目マージは「配置先にしか無い設定を
消さない」ために作ったが、守る対象が実在しないか、むしろ上書きされるべきものだった。そして
このセッションで見つかった不具合 — 同じ matcher のフック消失、大小文字の畳み込み、`keybindings` の
チョードだけが消える、`themes: []` が配置先のテーマ定義を削除する、意図的に消した action の復活、
`[[keys.command]]` があると何も配られない、冪等性違反 — は**すべてマージ機構だけが原因**だった。
加えてマージには削除の概念が無く、dotfiles からキーを消してもマシンから消えないため、
「dotfiles が正」を今の実装は満たしていない。

**Prerequisites**: none

**Steps**:

- [x] `setup.sh` の `merge_json` / `merge_toml` / `merge_config` / `drop_identical_backup` を削除し、herdr・WT・Claude Code の3経路を丸ごと上書きに戻す。配置は1つの関数(`deploy`)に集約する
- [x] `lib/merge.py` を削除する。`tests/` からマージ専用のもの(`suite.py` / `fuzzmut.py` / `fuzzrand.py` / `h.py` と、`realdata.sh` のマージ検証部)を削除する。`tests/` が空になるなら README ごと落とす
- [x] 配置先が原本と違うときの退避は残す。原本と同じ内容なら何も書かず退避も取らない。配置に失敗して
      配置先が無傷なら、直前に取った退避は捨てる(残すと失敗のたびに同一の `.bak` が1本ずつ増える)
- [x] 配置を原子的にする(同じディレクトリの一時ファイルに書いてから `mv`)— 中断で切り詰められた
      JSON / TOML を残さない。項目マージが持っていた保証なので、撤去で落とさない
- [x] 失敗の扱いも1種類に揃える: どのファイルでも配置に失敗したら警告して残りは続行し、run の
      最後に失敗を列挙して非0で終わる。`Done.` は全部配置できた run だけが出す
- [x] `design.md` の §4.7(項目マージの保証・id 突き合わせ・4系統の終末)と、それを参照している箇所を撤去し、「全部上書き、dotfiles が正」に書き換える。§4.4 の未使用 action の話も上書き前提に戻す。§5.1 の「守る対象が実在しない」は「現時点では実在しない(Windows 1台の前提)」に限定する
- [x] mac で `setup.sh` を実行し exit 0、herdr config / Claude settings / statusline.sh / iTerm2 プロファイルが dotfiles の内容そのものになることを確認。2回流して冪等であることも確認
- [x] WSL 経路は mac で実行できないため、`uname` シムとスタブで到達して確認する。あわせて WSL でない Linux で `wslpath` 不在により落ちる既存の穴(レビュー指摘)を塞ぐ
- [x] 未検証のまま残るものを記録する: WT が WSL プロファイルを作り直すか(WSL 実機)、Windows 実機への配置、
      iTerm2 が DynamicProfiles のドット始まりファイルを読むか。README が #8 まで旧方式のままであること
- [x] self-check (OK/NG per completion criterion, record in checks/10.md)
- [ ] QA expert review (subagent)
- [ ] Design expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- `lib/merge.py` が存在せず、`setup.sh` にマージ経路が残っていない。管理対象のファイルは
  すべて同じ1つの方式(丸ごと上書き)で配置される
- mac 上で `setup.sh` が exit 0 で完了し、配置された4ファイルが dotfiles の内容と一致する。
  2回流してもバイト列が変わらない
- `herdr config check` が配置後の config.toml に対して通る
- WSL でない Linux で `wslpath` 不在により setup が落ちない
- `design.md` と `steering.md` と `setup.sh` が同じことを言っている(項目マージへの言及が残らない)

### #14: フォントサイズを 14 にする

**Purpose**: 13pt が小さいというユーザーの判断。統一仕様の変更。

**Prerequisites**: none

**Steps**:

- [x] `iterm2/herdr.json` の `Normal Font` を `HackGenConsoleNF-Regular 14` にする
- [x] `windows-terminal/settings.json` の `profiles.defaults` のフォントサイズを 14 にする
- [ ] 配置して mac で実機確認(ユーザーが見て判断する)
- [x] self-check (OK/NG per completion criterion, record in checks/14.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- 両OSの端末設定でフォントサイズが 14 になっている。README は数字を持たない(#8 の規則)
- iTerm2 で実際に 14pt で表示されることをユーザーが確認している

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

### #12: テーマの三層をユーザー指定どおりに揃える

**Purpose**: テーマは3層ある — 端末そのもの、herdr の UI、Claude Code の UI。ユーザーの指定は
端末 = Gruvbox Dark / herdr = `gruvbox-light` / Claude Code = 組み込み `light`。dotfiles 側が
herdr に `gruvbox`(dark)、Claude Code に `custom:catppuccin-mocha` を持っていて setup のたびに
指定から巻き戻る状態を解消し、参照されなくなるカスタムテーマの実体を落とす。

**Prerequisites**: none

**Steps**:

- [x] `herdr/config.toml` の `[theme] name` を `gruvbox-light` にする
- [x] `claude/settings.json` の `theme` を `light`(組み込み)にする
- [x] 参照されなくなる `claude/themes/catppuccin-{mocha,latte}.json` を削除し、steering の
      Acceptance criteria・#6/#7/#8/#10 の themes 関連の記述を落とす
- [x] steering の Acceptance criteria の「herdr の UI テーマが `gruvbox`(dark)であること」を
      `gruvbox-light` に改める(#5 の revise (c) の判断を差し戻すことになるため、評価ゲートで承認を取る)
- [x] README と design.md の記載を3層すべてについて合わせる(端末は Win/Mac それぞれの設定箇所を明示)
- [ ] self-check (OK/NG per completion criterion, record in checks/12.md)
- [ ] QA expert review (subagent)
- [ ] Craft expert review (subagent, per the task's medium)
- [ ] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- `herdr/config.toml` の `[theme] name` が `gruvbox-light`、`claude/settings.json` の `theme` が
  `light`、端末側(WT の `profiles.defaults.colorScheme` / iTerm2 `herdr.json` の色)が Gruvbox Dark
- `claude/themes/` が存在せず、dotfiles・steering・design・README のどこからも参照されていない
- README と design.md にテーマ3層の対応が書かれていて、steering の Acceptance criteria と一貫している


### #15: ステータスラインのモデル名表示を家族名+版に統一する

**Purpose**: 現行の1文字略記(`O5`)は読み手が対応表を覚えていないと判別できず、節約は数文字しかない。
さらに置換規則が `Opus` / `Sonnet` / `Haiku` の列挙なので `Fable` が素通りし、`(1M context)` の注記も
そのまま出る。注記はコンテキスト量を `C:` セグメントで既に出しているため重複でもある。家族名を
列挙しない1本の規則に置き換え、`Opus5` / `Sonnet5` / `Fable5` / `Haiku4.5` の形にする。

**Prerequisites**: none

**Steps**:

- [x] `claude/scripts/statusline.sh` のモデル略記処理を、括弧注記の除去 → `Claude ` 接頭辞の除去 →
      空白の除去、という家族名に依存しない規則に置き換える(`6bab994`)。レビューで sed が mac=BSD /
      WSL=GNU で割れることが実測されたため、正規化は jq 側に移した(`f740dcb`)— jq は既に必須依存で、
      実測上どちらのホストでも同じ結果を返す。あわせて `echo` を `printf` に置換(7箇所)— どちらの
      シェルの `echo` もバックスラッシュを展開して JSON を壊していた既存の穴
- [x] 実際の入力形状で確認する: `Opus 5 (1M context)` / `Sonnet 5` / `Fable 5` / `Haiku 4.5` /
      `Claude Sonnet 4.5`、および `display_name` が無く `model.id` にフォールバックする形状と、
      `effort.level` の有無の両方
- [x] `sh -n` と `dash -n` で構文検証し、`~/.claude/scripts/statusline.sh` に配置して実表示を確認する
- [x] self-check (OK/NG per completion criterion, record in checks/15.md)
- [x] QA expert review (subagent)
- [x] Craft expert review (subagent, per the task's medium)
- [x] Verification expert review (subagent, per the task's medium)

**Completion criteria**:

- `display_name` が `Opus 5 (1M context)` のとき第2セグメントのモデル部が `Opus5` になり、
  `Sonnet 5` → `Sonnet5`、`Fable 5` → `Fable5`、`Haiku 4.5` → `Haiku4.5` になる。
  括弧の注記は表示に残らない
- 置換規則が特定の家族名を列挙していない — 新しい家族名が来ても素通りせず同じ形に整う
- 第1・第3セグメントと `/努力度` の付き方は従来どおりで、区切りは `|` のまま。
  steering の Acceptance criteria が書く表示形式(`C:…k/…k 5h:…% 7d:…% | モデル/努力度 |
  ディレクトリ@ブランチ`)から外れない
- `sh -n` / `dash -n` が通り、`display_name` 不在(`model.id` フォールバック)や `effort.level`
  不在でも壊れない

# State

(written by /rn:dn, read and reset to this placeholder by /rn:up. `Status` is `paused` while a
session is suspended — the signal /rn:up and /rn:dn search for — and resets to `not suspended` here,
so only a genuinely suspended session reads `paused`.)

- **Status**: paused
- **Date**: 2026-09-05
- **Next**: #10 — 実装は `a873819` まで入り自己検証済み。QA と Verification の再レビューを回し、
  指摘を反映してからチェックオフする
- **Last completed**: #15(ステータスラインのモデル名 — `1543933` でチェックオフ済み)
- **Notes**: branch `worktree-herdr4mac` / PR https://github.com/lovaizu/dotfiles/pull/8(draft)。
  実施順は #10 → #8 → #11 → #12 → #5。
  **#14 はユーザーの実機確認待ち** — iTerm2 で新規ウィンドウを開き 14pt の見え方を判断してもらう。
  それが取れたらレビュー3件を回してチェックオフ。
  **#10 の再レビュー**: QA と Verification は `a873819` に対して未実施(前ラウンドはこの2人が
  データ消失と tty での偽成功を実測で見つけた)。Craft の再レビューは `f03f513` を対象に走らせた
  ままセッションを閉じたので結果は取れていない — 現行コードに当てはまる指摘だけ拾い直すこと。
  **次回 Windows 同期時にやること**: WT が WSL プロファイルを作り直すかの検証(撤回判断を支える
  唯一の未検証事項)、ctrl+alt 系キーの確認、WT settings.json の上書き結果の確認。
  README は #8 まで旧方式(項目マージ前提)のままである点に注意。
  未追跡のまま残した: `?? .rn/20260822-herdr4mac/checks/10.md` `?? .rn/20260822-herdr4mac/checks/14.md`
