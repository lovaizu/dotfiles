# Goal

`~/work/<group>` の下で端末から起動すると、そのグループの Docker Sandbox (`sbx`) の中で herdr が開き、
Claude Code がホストと同じ前提(`CLAUDE.md`・statusline・rn plugin・herdr 連携)で動く(Issue #24)。
sandbox の中では手で何も設定しない。

ねらいは、承認の確認なしで Claude を動かしても、届く範囲をグループのディレクトリに限ること。
sandbox の中では Claude Code は既定で `--dangerously-skip-permissions` で動く。

# Acceptance criteria

- `~/work/<group>` の下のどこで起動しても、そのグループのディレクトリをマウントした同じ sandbox につながる。
  `~/work/<group>` の外では何もマウントせず、理由を出して止まる
- sandbox の中で herdr が開き、そのペインから起動した Claude Code に `CLAUDE.md`・statusline・rn plugin・
  herdr の Claude 連携が効いている
- 同じグループの Claude のセッション同士でメッセージが届く
- `~/.claude/settings.json` には repo のキーがマージされ、sbx が書いたキーは残る
- GitHub のトークンと Claude のログインは VM に入らない(中から見えるのは偽の値)。
  トークンも Claude のログインも repo には入らない
- ホストで herdr を呼ぶキーが、sandbox の中の herdr を開く。ホストの herdr の中に sandbox の herdr が入る二重にはならない
- sandbox を作り直しても(`sbx rm` のあと)、同じ手順で同じ状態に戻る

# Assumptions

- sbx の動き(公式ドキュメントを読んだ、2026-10-20):
  - 入れ方: `brew trust docker/tap && brew install docker/tap/sbx`、`sbx login`(Docker アカウント。ローカル利用は無料)。
    Apple silicon、macOS 14 以上。Docker Desktop は要らない
  - sandbox 1つが microVM 1台。`sbx run claude <dir>` で `<dir>` をホストと同じ絶対パスにマウントし、そこで Claude を起動する。
    同じパスでもう一度実行すると同じ sandbox につながる。追加のディレクトリも同じパスでマウントでき、`:ro` で読み取り専用
  - VM の中の状態(`/home/agent`、入れたツール)は `sbx rm` まで残る
  - 外への通信はホスト側の proxy を通り、proxy が認証ヘッダを差し込む。VM の中は偽の値だけ
  - sbx はホストの環境変数を自動では読まない。`sbx secret set github --command '...'` でホストでコマンドを実行して取る。
    secret はキーチェーンに入る
  - Claude のログインは sandbox の中で `/login`。OAuth はホスト側で行うとある。sandbox ごとに要るか、どれだけ持つかは書いていない
- kit の仕様(公式ドキュメント kits-v2 を読んだ、2026-10-20):
  - `spec.yaml`。`kind: sandbox` で `extends: claude` にすると Claude の kit を引き継げる。
    `sandbox.entrypoint` / `sandbox.command` で起動するものを置き換えられる(`command` は引き継いだ引数を丸ごと置き換える)
  - `setup.install` は作成時に1回、root で `sh -c`。`setup.startup` は起動のたびに agent(UID 1000)で、
    対話なし・何度流しても同じであること。`setup.files` と `files/home/` は `/home/agent/` に置く
  - kit はローカルのディレクトリ・Git の URL(`git+https://...#ref=<commit>&dir=<dir>`)などから読める。
    `sbx run claude --kit <kit>` で足す。kit の組み合わせは作成時に決まる
  - kit からホストの環境変数やファイルは読めない。認証情報は `sbx secret set` で渡す
- このMacの GitHub トークン(2026-10-20 確認):
  - kiyobot の `GH_TOKEN` だけで gh を使っている。`cc()` の外では gh はどのアカウントにもログインしていない。
    なので `--command 'gh auth token'` は sbx の常駐プロセスからは取れないはず
  - トークンのファイルは `~/work/lovaizu/.env` から `~/.config/kiyobot.env` に移した(マウントの外へ。ユーザー判断)。
    `~/.zshrc` の `cc()` も合わせた。`~/.zshrc` は repo の外の手書き部分
  - sbx には `--command 'sh -c ". ~/.config/kiyobot.env && printf %s \"\$GH_TOKEN\""'` で渡す想定
- `./setup.sh` は chezmoi の適用。`settings.json` は repo のキーだけマージ、端末とフォントの手順は macOS と WSL のときだけ。
  sandbox の中でそのまま動くかは未確認。Linux の手順は jq を `sudo apt-get` で入れる
- 素の sandbox で確かめたこと(sbx 0.48.0、`sbx create --name lovaizu claude ~/work/lovaizu`、2026-10-20):
  - 中は Ubuntu 26.04、kernel 7.0.14、ユーザーは agent(UID 1000、sudo グループ)。jq は最初から入っている
  - 見えるのは `/Users/kiyo/work/lovaizu` だけ。その上の `/Users/kiyo/work` は VM の中に作られたディレクトリで、
    sbx が `CLAUDE.md`(約18KB、sandbox での作業の説明。`/etc/sandbox-persistent.sh` など)と空の `kits-agent-context` を置く。
    親のディレクトリの `CLAUDE.md` なので、`lovaizu` の下で起動した Claude は毎回これも読む。ホストにはない
  - `GH_TOKEN` は `gho_sbxproxymanaged...` という偽の値。それでも `gh api user` は kiyobot を返す
  - sbx が最初に書く `settings.json` は `permissions.defaultMode: bypassPermissions`・`bypassPermissionsModeAccepted`・
    `skipDangerousModePermissionPrompt`・`alwaysThinkingEnabled`・`themeId`
  - 外への通信は、ネットワークの方針を決めるまで sandbox を作れない。`sbx policy init balanced` にした(ユーザー判断)。
    balanced では get.chezmoi.io・herdr.dev・starship.rs が止まる(403)。
    `sbx policy allow network --sandbox lovaizu ...` でこの sandbox だけに許した。github.com は最初から通る
  - 許したあと中で worktree の `./setup.sh` を流すと: chezmoi 2.73.2・herdr 0.9.5・starship 1.27.0 が入り、
    `CLAUDE.md`・statusline・herdr の設定が置かれ、rn plugin と herdr 連携が入った。WSL の手順は動かなかった。
    `settings.json` には repo のキーがマージされ、sbx のキーは全部残った。2回目は exit 0
  - `sbx exec` では `SHELL` が空なので、`.chezmoiignore` が `.bashrc` も `.zshrc` も外し、プロンプトの読み込み行が入らない。
    `sbx exec -it lovaizu herdr` で開いた herdr のペインも `$` だけの sh(dash)になり、`Ctrl+L` が `^L` と出る。
    agent のログインシェルは `/bin/bash`。kit では `SHELL` が渡るようにする
- このセッションのフック(worktree の外の git を止めるもの)は、`sbx exec` に渡すコマンドに `git`・`sudo`・`sh -c` の文字列があると止める。
  `sbx secret set` はユーザーが iTerm の別のタブで実行した
- ユーザー判断(2026-10-20):
  - マウントするのは起動したディレクトリではなく、それが属する `~/work/<group>`。
    起動したディレクトリそのままだと、同じグループが別々の sandbox に分かれ、`$HOME` で起動すると丸ごとマウントされる
  - `cc()` は #24 が終わるまで残す。消すかはそのときに決める
  - #21 は #24 のあとに、この sandbox の中でやる

# Rules

- commit and push every change
- 会話・`.rn/` は日本語。コード・コミットメッセージ・PR は英語
- 過去セッションの `.rn/` 配下は読むだけで書き換えない
- sandbox は `sbx rm` で消せるので、試すのは本物の sandbox で。ホストの `$HOME` を変えるときはユーザーに断ってから
- README は、読み手が作業の結果から読み取れずに間違えることがあるときだけ変える
- 決めることはユーザーに1つずつ聞く
- レビューは目的に錨を下ろす。1人用 dotfiles。完了基準に照らして効かない指摘は挙げさせない

# Tasks

### #1: sbx を入れて、素の sandbox で `./setup.sh` を試す

**Purpose**: kit を作る前に、今の chezmoi の構成が sandbox の中でどこまで動くかを実物で知る。

**Steps**:

- [x] ユーザーが sbx を入れて `sbx login` する(2026-10-20 sbx 0.48.0)
- [x] Issue #24 の Desired State に、グループのディレクトリから起動するコマンドを書き足す(2026-10-20)
- [x] GitHub トークンを `sbx secret set github --command ...` で渡し、中から `gh api user` が kiyobot を返すか見る
- [x] sandbox を作る(`sbx create --name lovaizu claude ~/work/lovaizu`)
- [ ] ユーザーが `sbx run --name lovaizu` で中の Claude を開き、`/login` する。`CLAUDE.md`・statusline・rn が効いているか見る
- [x] 中で `./setup.sh` を流す。見ること: エラー、`settings.json` に sbx のキーが残るか、rn plugin と herdr 連携が入るか、
  WSL と判定されないか、jq の `sudo` が通るか

### #2: kit で sandbox に repo を持ち込み、chezmoi で適用する

**Purpose**: sandbox を作ると、手を動かさずに #1 で確かめた状態になる。

**Steps**:

- [ ] kit(`spec.yaml`)の形を読み、repo の置き場所を決める
- [ ] 作成時と起動のたびにすることを分けて書く
- [ ] `sbx rm` から作り直して、同じ状態になるか確かめる

### #3: herdr を sandbox の入口にする

**Steps**:

- [ ] `extends: claude` の kit で herdr を入口にできるか見る。できなければ ypxing/sbx-agent-kits の herdr mixin を読む
- [ ] 同じ sandbox のペイン同士で Claude のメッセージが届くか見る

### #4: ホストから起動する

**Steps**:

- [ ] `~/work/<group>` を割り出して sbx を起動するコマンドを作る
- [ ] ホストで herdr を呼ぶキーから、そのコマンドを起動する

**Completion criteria**:

- Acceptance criteria の各項目を、このMacの本物の sandbox で確かめている
