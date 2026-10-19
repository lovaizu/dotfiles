# Goal

`setup.sh` の自前の「ファイルを置く仕組み」(`lib/deploy.sh` の `deploy()` / `backup_file()`)をやめ、
chezmoi で設定を管理する(Issue #17)。

いまは設定の種類を足すたびに、置く仕組みの安全性(途中で壊れない・何度流しても同じ・失敗の伝え方)を
設計し直して確かめ直している。さらに repo から消したファイルがマシンに残り続ける。
自前の実装はできるだけなくし、chezmoi の標準のやり方に合わせる。合わないところだけ自前で残す。

# Acceptance criteria

- 新しいマシンで chezmoi の初期化と適用を1回流すと、いまの `./setup.sh` と同じ状態になる:
  herdr・iTerm2・Windows Terminal・Claude Code の設定、フォント、herdr / jq / starship、
  ccpm プラグイン、herdr の Claude Code 連携、⌘英かな、Starship のプロンプト、WSL のホスト名
- ファイルを置く自前の仕組み(`lib/deploy.sh` に当たるもの)が repo に残らない
- ファイルの置き換えは途中で止まっても壊れない(chezmoi が一時ファイル→名前の変更で書く)
- 失敗があれば0以外で終わり、何が失敗したかが分かる。失敗があっても他は最後まで進む
- repo から消したファイルは、同じコミットで `.chezmoiremove` に書けばマシンからも消える
- 前回の適用のあとに手で変えたファイルは、上書きの前に聞かれる。聞く相手がいない(端末がない)ときは
  上書きせず失敗として終わる
- 持ち主が他にいるファイル(herdr のフックスクリプトなど)には触らない
- 2回目以降の適用で、変わっていないものは何もしない

# Assumptions

- Issue の Desired State にある「ファイルごとに分かるバックアップ」は持たない。代わりに上の
  「上書き前に聞く」と git の履歴で戻す(2026-10-18 ユーザー判断: ベストプラクティスに合わせ、自前実装を減らす)
- chezmoi は repo から消したファイルを自動では消さない(`.chezmoiremove` か `exact_` が要る)。
  `~/.claude` などはアプリが自分でファイルを置くので `exact_` は使えない(公式ドキュメントで確認)
- chezmoi の書き込みは renameio による一時ファイル→名前の変更(ソース `realsystem_unix.go` で確認)
- chezmoi v2.73.2 を Homebrew でこのMacに入れた。XDG_CONFIG_HOME / XDG_STATE_HOME はこのMacでは未設定
- 別の HOME で確かめた動き(chezmoi v2.73.2、2026-10-18):
  - 初回の適用では、既にある違う中身のファイルを聞かずに上書きする。このMacで置かれている5つのファイルは
    repo と同じ中身なので、移行で失うものはない(`cmp` で確認)。新しいマシンには元々ファイルがない
  - 手で変えたあとは「has changed since chezmoi last wrote it」と聞く。端末がなければ上書きせず exit 1
  - repo から消しただけではマシンのファイルは残る。`.chezmoiremove` に書くと消える
  - `run_` スクリプトが失敗すると exit 1。ファイルは置かれたまま。`--keep-going` で他も最後まで進む
- Claude Code と herdr は `~/.claude/settings.json` に自分で書き戻す(hooks・enabledPlugins)。
  このMacでは setup.sh が入れていない `writ@ccpm` も有効になっていて、いまの丸ごと上書きは毎回これを消している。
  modify テンプレートで repo のキーだけを上書きし、他のキーを残せることを別の HOME で確かめた
- Windows Terminal の設定は `$HOME` の外(Windows 側の AppData)にある。chezmoi は `$HOME` の下だけを扱う
- ユーザー判断(2026-10-18):
  - settings.json は repo のキーだけを上書きし、アプリが書き足したキーは残す
  - Windows Terminal は WSL の適用1回のまま、スクリプトで Windows 側へコピーする。
    Windows にも chezmoi を入れる案は、この1ファイルのために Windows の手順が2回になるので割に合わない
  - Mac のツールは Homebrew(Brewfile)に一本化する。このMacの `~/.local/bin/herdr`(0.9.1、#26 より前の残り)は、
    動いている herdr を閉じたあとに消す。試したときに Homebrew の herdr 0.9.5 と jq 1.8.2 が実機に入った
  - 使い方はこれまで通り「clone して `./setup.sh`」。`setup.sh` は `chezmoi generate install.sh` の公式の入口
    (chezmoi がなければ入れて、その clone を適用する)に `--keep-going` を足しただけ。
    一度は chezmoi 専用の clone を持たせると決めたが、ユーザーのイメージと違ったので決め直した(2026-10-19)
- chezmoi は親ディレクトリの権限も揃える。`~/.config` と `~/Library` は 700 なので `private_` を付けた
  (付けないと 755 に広げる差分が出た)
- Ubuntu 24.04 のコンテナで WSL を真似て試した(2026-10-19。kernel の osrelease を差し替え、cmd.exe / wslpath は偽物):
  herdr / jq / starship が入り、`.bashrc` に読み込み行が1回だけ足され、Windows Terminal の設定がコピーされ、
  ccpm プラグインと herdr 連携が入った。2回目は何も増えない。ホスト名だけは distro の再起動が要るので毎回 exit 1
  (コンテナでは再起動できない)
- Windows 側は実機で確かめる必要がある(このMacからは確かめられない)

# Rules

- commit and push every change
- 会話・`.rn/` は日本語。コード・コミットメッセージ・PR は英語
- 過去セッションの `.rn/` 配下は読むだけで書き換えない
- 試すときは実際の `$HOME` ではなく別の HOME を使う。実際の `$HOME` への適用はユーザーに断ってから
- README は、読み手が作業の結果から読み取れずに間違えることがあるときだけ変える
- 決めることはユーザーに1つずつ聞く
- レビューは目的に錨を下ろす。1人用 dotfiles。完了基準に照らして効かない指摘は挙げさせない

# Tasks

### #1: chezmoi の動きを別の HOME で確かめる

**Purpose**: 移し方を決める前に、Acceptance criteria に関わる chezmoi の動きを実物で知る。

**Steps**:

- [x] herdr の設定1つで、初回適用・2回目・手で変えたあと・repo から消したあとの動きを見る
- [x] 失敗したときの終了コードと、`--keep-going` で他が最後まで進むかを見る
- [x] アプリが書き戻すファイル(settings.json)の扱い方を決める

### #2: 設定ファイルを chezmoi のソースに移す

**Purpose**: herdr・Claude Code・シェルのプロンプト・iTerm2 の設定が chezmoi の適用で置かれる。

**Steps**:

- [x] repo の置き場所と、新しいマシンでの始め方を決める
- [x] ファイルを移し、Mac / WSL で要らないものは `.chezmoiignore` で外す
- [x] Windows Terminal の置き方を決めて移す

### #3: インストールや登録の処理を chezmoi のスクリプトに移す

**Purpose**: ツール・フォント・プラグイン・herdr 連携・⌘英かな・プロンプトの読み込み行・WSL のホスト名が、
適用の中で用意される。

**Steps**:

- [x] Homebrew で入れるものは Brewfile にまとめる
- [x] 残りを `run_` スクリプトに移す。失敗は0以外で終わらせる
- [x] `setup.sh` と `lib/` を消す

### #4: 実機で確かめる

**Steps**:

- [ ] ユーザーに断ってから、このMacの実際の `$HOME` に適用し、Acceptance criteria を確かめる
- [ ] WSL で確かめてもらう

**Completion criteria**:

- Acceptance criteria の各項目を、Mac と WSL の実機で確かめている
