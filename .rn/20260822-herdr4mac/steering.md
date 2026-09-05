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

**対象は端末環境だけ**。Claude Code のユーザー設定を同じ仕組みに載せる話は、このセッションの
途中で取り込んだあと切り離した — 端末の統一とは独立に決めるべきことが多く、1つの PR に混ぜると
判断がまとまらないため。要望は Issue に移した(#9 settings.json / statusline.sh、#10 CLAUDE.md)。

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
  - Default プロファイルから引き継ぐと Gruvbox Dark 上で読めなくなる色を残さない
- windows-terminal/settings.json が統一仕様に整理されている: 即時切替は `ctrl+alt` 系のみ
  (`ctrl+shift` / `alt+shift` の別名チョードは削除)、`⇧Enter`→`\n`・`ctrl+t` 無効化・外観・
  プロファイル定義は維持
- `setup.sh` が共通部(herdr config)+OS別(darwin: iTerm2 Dynamic Profile 配置と、Homebrew が
  あれば HackGen フォントのインストール / WSL: WT settings.json 配置)の構成で、両OSで
  **配置に失敗しなければ** exit 0 で完了する(darwin では `wslpath`/`cmd.exe` 不在で落ちない、
  WSL でない Linux でも落ちない — WSL かどうかは `/proc/sys/kernel/osrelease` で判定する。
  WSL なのに Windows 側へ届かない場合(interop 無効)はスキップではなく配置失敗として数える)。
  配置に失敗した run は警告を出して残りを続行し、最後に失敗を列挙して非0で終わる
- herdr/config.toml は OS 共通のまま(OS 別の分岐を持ち込まない)。`[keys]` は変更しない。
  `[theme]` は herdr の UI テーマが `gruvbox-light` であること — 端末そのものは Gruvbox Dark で、
  herdr の UI だけ light にする(ワークスペースの選択状態を判別しやすくするためユーザーが意図した配色)
- **dotfiles が正**。setup.sh は管理対象のファイルをすべて丸ごと上書きする — 配置方式は1種類だけで、
  ファイルごとの例外を持たない。dotfiles が持つ設定がそのマシンの設定であり、dotfiles からキーを
  消せばマシンからも消える。項目単位でマージする機構は repo に存在しない
- 配置先が dotfiles の原本と違うとき、上書きの前に BACKUP_DIR へ退避する(**例外**: 配置先がリンク先の
  存在しない symlink のときは、退避すべき内容が無いので退避を取らずに置き換える — design.md §4.6 の境界)。
  載せ替えの初回だけでなく、アプリが設定を書き戻したあとの実行でも退避は起きる
  (herdr はテーマ名と `onboarding` を書き戻す)。
  世代管理も剪定もしないので BACKUP_DIR は増える — 不要になったらユーザーが消す。原本と同じ内容の
  配置先には何も書かず、退避も取らない

# Assumptions

- herdr の `config.toml` は OS 共通で、mac でもそのまま herdr の XDG パス
  (`${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml`)に置けば動く — 検証済み(配置後の
  config.toml が repo の原本と `diff` 一致し、`herdr config check` も `config: ok`(#10)、
  mac 実機での動作確認は #5 Steps)
- iTerm2 はユーザーがインストール済み。mac のフォントは Homebrew(cask `font-hackgen-nerd`)が
  あれば setup.sh で入れ、なければスキップ(手動導入でも可)。Win 側のフォントインストールは
  WSL からは行えないため手動(README に手順を記載)
- iTerm2 / WT の実機での鍵送信確認はユーザーが行う(エージェントは設定ファイルの静的検証まで)
- シェル自体は統一しない: Win は WT のプロファイル(PowerShell / WSL bash)、Mac は zsh のまま。
  herdr の起動は両OSとも手動
- `~/.config/herdr/config.toml` は herdr が実行時に書き戻す — 実証済み(setup.sh が repo 版
  363 B `name = "gruvbox"` を配置したのち、52 分後には 369 B `name = "gruvbox-light"` に変化)。
  `onboarding = false` の存在と `herdr config reset-keys` の存在も herdr 側が所有者であることを示す
- WT の `settings.json` も WT 自身が書く。`profiles.list` にはそのマシンの WSL ディストロ由来の
  GUID が入るが、これは WT がそのマシンで生成し直す在庫情報なので丸ごと上書きして構わない、
  という判断を採っている。**この「WT が作り直す」は WSL 実機で未検証の仮定**であり、
  丸ごと上書きの正しさを支える唯一の未検証事項として残る(検証は次回 Windows 同期時)
- **Windows マシンは1台**。`windows-terminal/settings.json` は `profiles.list` にそのマシンの
  WSL ディストロ由来の GUID を抱えたまま配布されるので、丸ごと上書きが成り立つのはこの前提の下だけ。
  2台目に配ると、そのマシンに無いディストロの GUID が持ち込まれ、固有の GUID は消える
  (design.md §4.6 の境界。台数が増えた時点でこの判断はやり直しになる)

# Rules

- commit and push every change; one completion marker per task
- 会話・ドキュメントは日本語(コード・コミットメッセージは英語)
- herdr/config.toml の `[keys]` には手を入れない(`[theme]` は端末側と揃えるため変更可)
- このファイルと design.md、checks/ は**常に最新状態に保つ**。変更履歴・撤回した内容の手順・
  実施済みレビューのチェックボックスは残さない — それらは git log と成果物から辿れる。
  残すのは「なぜそうしたか」と、決定に紐づくレビュー指摘・対応要否・対応内容

# Tasks

## 完了

### #1: README に統一仕様を定義する

**Purpose**: 両OSで揃える使い勝手とセットアップ手順を README に明文化し、以降のタスクの仕様源にする。

**Completion criteria**:

- README に対応表があり、即時切替3操作(previous/next workspace, next agent)・⇧Enter・⌃T
  パススルーについて Win / Mac 双方のキーと送信内容(herdr 列)が読み取れる
- テーマ・フォントと、両OSのセットアップ手順(フォントの入手方法含む)が記載されている
- 記載内容が Acceptance criteria の対応表と矛盾しない

レビュー: `checks/1.md`。**#8 で書き直す** — 具体的な設定値を README に置いたことが2か所メンテを生んだ。

### #2: iTerm2 Dynamic Profile を作成する

**Purpose**: 統一仕様を iTerm2 の語彙(Keyboard Map と色定義)に翻訳し、JSON 1ファイルで完結させる。

**Completion criteria**:

- `iterm2/herdr.json` が有効な JSON で、Dynamic Profile の必須キー(Guid, Name)を持つ
- Keyboard Map に4エントリが存在し、キーコード(修飾フラグ含む)と送信バイト列が README の対応表
  (⌃⌘[→`^T [`, ⌃⌘]→`^T ]`, ⌃⌘U→`^T u`, ⇧Enter→`\n`)と一致する
- 色定義が windows-terminal/settings.json の Gruvbox Dark スキームの16色+前景/背景と同一の値である

レビュー: `checks/2.md`。**完了基準に欠陥があった** — ANSI 16 色 + 前景/背景/カーソル/選択に
限られていたため、未定義の色キーが Default プロファイルから引き継がれる問題が素通りした(#11)。

### #3: Windows Terminal 設定を統一仕様に整理する

**Purpose**: 別名チョード(`ctrl+shift` / `alt+shift` 系)を削除し、即時切替を `ctrl+alt` 系のみに
統一して README の対応表と1:1 にする。

**Completion criteria**:

- settings.json が有効な JSON で、即時切替の keybinding が `ctrl+alt+[/]/u` の3つのみになっている
- `⇧Enter`→`\n`、`ctrl+t` 無効化、`ctrl+c/v`・`ctrl+shift+f`・`alt+shift+d`、外観、
  プロファイル定義に変更がない
- 未使用になった action 定義が残っていない

レビュー: `checks/3.md`

### #4: setup.sh を共通部+OS別構成に再編する

**Purpose**: OS 判定を導入し、共通部(herdr)のあと darwin では iTerm2 設定配置+フォント、
WSL では WT 配置を行うようにする。

**Completion criteria**:

- mac 上で `setup.sh` が exit 0 で完了し、iTerm2 の DynamicProfiles と `~/.config/herdr/config.toml` が
  配置されている
- darwin では `wslpath` / `cmd.exe` 不在でもエラー終了せず、WT ブロックに到達しない
- WSL 経路は herdr config + WT settings.json を同じ場所に配置する
- Homebrew 不在の mac でもエラー終了しない

レビュー: `checks/4.md`

### #16: PR から Claude Code 設定を外す

**Purpose**: このセッションで取り込んだ Claude Code のユーザー設定を PR から切り離し、端末環境の
統一だけを残す。要望は Issue #9 に移してある。混ぜたままだと、端末側の判断と Claude Code 側の
判断(プラグイン実体の再現方法、どの設定を dotfiles で固定するか)が同じ PR で絡まる。

**Completion criteria**:

- `claude/` が repo に存在せず、`setup.sh` に Claude Code への言及が残っていない
- mac 上で `setup.sh` が exit 0 で完了し、配置された2ファイル(`config.toml` と `herdr.json` —
  `settings.json` は WSL 専用)が dotfiles の内容と一致する。
  2回流してもバイト列が変わらない
- 配置失敗時の挙動(警告 → 続行 → 末尾で列挙 → 非0)が #10 の完了基準のまま保たれている

レビュー: `checks/16.md`。**削除は grep で終わらなかった** — 消したファイルを worked example や
`(measured)` の対象にしていたコメントが4件あり、`grep -i claude` では見つからない。直した先で
さらに全称の言い過ぎが3件出て、コメントだけで4ラウンド回した(コード行は初回から不変)。
最後は `herdr config check` が `[keys]` の消えた config を `config: ok` と言うことを実測でき、
代役の parser ではなく読み手本人の証拠に差し替わった。

## 未完了

### #10: 配置を丸ごと上書きに統一し、項目マージ機構を撤去する

**Purpose**: 「dotfiles が正」という原則に実装を合わせる。項目マージは「配置先にしか無い設定を
消さない」ために作ったが、**マージには削除の概念が無く、dotfiles からキーを消してもマシンから
消えない** — 原則をそもそも満たせない。守る対象の実在性については design.md §5.1。

**Prerequisites**: none

**Steps**:

- [x] 実装(`3ae7535` `f03f513` `a873819`)
- [x] 未対応の指摘11件を反映し、design.md §4.6 を結果に揃える(`c1497d7` `a1b641b`)
- [ ] QA / Design / Craft / Verification expert review — 最終形の setup.sh に対して回す

**Completion criteria**:

- `lib/merge.py` が存在せず、`setup.sh` にマージ経路が残っていない。管理対象のファイルは
  すべて同じ1つの方式(丸ごと上書き)で配置される
- mac 上で `setup.sh` が exit 0 で完了し、配置されたファイルが dotfiles の内容と一致する。
  2回流してもバイト列が変わらない
- 配置先(herdr が実際に読むパス = `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml`)と repo の
  原本が `diff` で一致する。`herdr config check` は補助 — 配置されたものが TOML としても妥当である
  ことの追加検査であって、単体では判定にならない(config.toml が無くても、空でも、`[keys]` を落としても
  `config: ok` / exit 0 を返す)
- WSL でない Linux で `wslpath` 不在により setup が落ちない
- `design.md` と `steering.md` と `setup.sh` が同じことを言っている

自己検証: `checks/10.md`

### #11: iTerm2 プロファイルの色定義の欠落を塞ぐ

**Purpose**: `iterm2/herdr.json` が定義していない色キーが iTerm2 の Default プロファイル
(Catppuccin Latte)から引き継がれ、Gruvbox Dark の背景に対して読めない色になる。

**Prerequisites**: #2

**Steps**:

- [x] `Bold Color`(`#ebdbb2`)・`Cursor Text Color`(`#282828`)・`Badge Color`(`#fb4934`)を追加(`c978b22`)。
      実機で太字が読めることをユーザーが確認済み
- [ ] 残りの未定義キー(`Link Color` / `Selected Text Color` / `Cursor Guide Color` /
      `Match Background Color` ほか)を洗い、実際の描画先に対するコントラストで要否を判断する
- [ ] self-check (OK/NG per completion criterion, record in checks/11.md)
- [ ] QA / Craft / Verification expert review

**Completion criteria**:

- `iterm2/herdr.json` が、iTerm2 の Default プロファイルから引き継ぐと Gruvbox Dark 上で
  読めなくなる色キーをすべて自前で定義している
- 各色が実際に描画される組み合わせ(太字は背景に、カーソル文字はカーソル色に、選択文字は
  選択背景に)で 4.5:1 以上のコントラストを持つ

### #12: テーマの二層をユーザー指定どおりに揃える

**Purpose**: テーマは端末そのものと herdr の UI の2層あり、ユーザーの指定は端末 = Gruvbox Dark /
herdr = `gruvbox-light`。dotfiles 側が herdr に `gruvbox`(dark)を持っていて setup のたびに指定から
巻き戻る状態を解消する。

**Prerequisites**: none

**Steps**:

- [x] `herdr/config.toml` の `[theme] name` を `gruvbox-light` にする
- [ ] README と design.md の記載を両層について合わせる(端末は Win/Mac それぞれの設定箇所を明示)
- [ ] self-check (OK/NG per completion criterion, record in checks/12.md)
- [ ] QA / Craft / Verification expert review

**Completion criteria**:

- `herdr/config.toml` の `[theme] name` が `gruvbox-light`、端末側(WT の
  `profiles.defaults.colorScheme` / iTerm2 `herdr.json` の色)が Gruvbox Dark
- README と design.md にテーマ2層の対応が書かれていて、Acceptance criteria と一貫している

### #14: フォントサイズを 14 にする

**Purpose**: 13pt が小さいというユーザーの判断。統一仕様の変更。

**Prerequisites**: none

**Steps**:

- [x] `iterm2/herdr.json` と `windows-terminal/settings.json` を 14 にする
- [ ] 配置して mac で実機確認(ユーザーが見て判断する)
- [ ] QA / Craft / Verification expert review

**Completion criteria**:

- 両OSの端末設定でフォントサイズが 14 になっている。README は数字を持たない(#8 の規則)
- iTerm2 で実際に 14pt で表示されることをユーザーが確認している

自己検証: `checks/14.md`

### #8: README を意図だけの記述に書き直す

**Purpose**: README が具体的な設定値を持っているため、値を変えるたびに2か所をメンテすることに
なっている(フォントサイズの変更で発覚)。README の担当を「何ができるか / なぜそうなっているか /
手でやるしかない箇所」に絞り、値は設定ファイル側にしか置かない。

**Prerequisites**: #16(配置対象が確定してから書く)

**Steps**:

- [ ] README から具体的な設定値を落とす: フォント名とサイズ、Gruvbox Dark の hex、テーマ名、
      キー対応表の送信バイト列。対応表の列は「操作 / Win キー / Mac キー」まで
- [ ] 残す意図を明示的に書く: 両OSで同じ指運びになる理由(HHKB の Alt と ⌘ が同じ物理位置)、
      `^T` が端末に横取りされず herdr に届くことが前提であること、端末は暗くその上の herdr UI は
      明るいのが意図した組み合わせであること(ワークスペースの選択状態を判別するため)
- [ ] 配置方式を1行で書く: dotfiles が正で、管理対象はすべて丸ごと上書き。手元で herdr UI から
      変えた設定を残したいなら dotfiles 側に入れる
- [ ] 値を落とした結果が `design.md` §3.2 / §4.1(README は値を持たない)と一致することを確認する
- [ ] self-check (OK/NG per completion criterion, record in checks/8.md)
- [ ] QA / Craft / Verification expert review

**Completion criteria**:

- README に具体的な設定値が残っていない — フォント名・サイズ、色の hex、テーマ名、送信バイト列を
  grep して0件。設定値を知りたい読者が、どの設定ファイルを見ればよいか分かる
- 記載された手順が実際の setup.sh の挙動と一致し、README 内の既存記述と矛盾しない

### #5: Evaluation sign-off

**Purpose**: Acceptance criteria の充足をユーザーに提示し、承認を得る。

**Prerequisites**: #8, #10, #11, #12, #14, #16

**Steps**:

- [x] mac の実機確認: iTerm2 で ⌃⌘[/⌃⌘]/⌃⌘U/⇧Enter/⌃T を raw モードで捕捉し
      `14 5b 14 5d 14 75 0a 14` — 全キー期待どおり。新規ウィンドウでワークスペース切替と
      herdr UI の配色も確認済み
- [ ] Acceptance criteria を1件ずつ検証した結果を提示する
- [ ] verdict を /rn:ty(approve)または /rn:gm(revise → 対応して再提示)で受ける

**Completion criteria**:

- Acceptance criteria の全項目に OK/NG と根拠が提示され、ユーザーが /rn:ty で承認している

**未確認のまま残るもの**(承認時にユーザーが受容するか判断する): Win 実機での ctrl+alt 系キー、
WT settings.json の上書き結果、WT が WSL プロファイルを作り直すか。いずれも次回 Windows 同期時。

## 撤回

- **#6 / #7 / #15** — Claude Code 設定(`claude/settings.json`・`claude/scripts/statusline.sh`)の
  dotfiles 化と、ステータスラインのモデル名表示。端末環境の統一とは独立に決めるべきことが多く、
  Issue #9 に移した。撤去は #16。
- **#9 / #13** — 項目マージのヘルパー実装と `lib/merge.py` への切り出し。撤回理由は #10 の
  Purpose と design.md §5.1。成果物は #10 で撤去済み。

# State

(written by /rn:dn, read and reset to this placeholder by /rn:up. `Status` is `paused` while a
session is suspended — the signal /rn:up and /rn:dn search for — and resets to `not suspended` here,
so only a genuinely suspended session reads `paused`.)

- **Status**: not suspended
- **Date**: -
- **Last completed**: -
- **Next**: -
- **Notes**: -
