# Goal

新しいマシンや新しい WSL の distro でも、`./setup.sh` を流すだけで次の2つがそろう(Issue #25)。

- プロンプトが Starship(既定の見た目)になる
- ターミナルのタブに「どの環境の、どのディレクトリか」が出る(例: `my: ~/work`)

タブが要るのは、Windows で distro を複数使うと、いまはどのタブも `ユーザー名@PC名` で見分けられないから。

# Acceptance criteria

- `./setup.sh` のあと新しいシェルを開くと、プロンプトが Starship の既定のもので、ホスト名を含まない
- herdr の外では、タブタイトルがプロンプトのたびに `<環境名>: <ディレクトリ>` になる(ディレクトリを移ると追従する)
- herdr の中では、タブタイトルが herdr 既定の `<環境名>: <スペース名>` になる
- 環境名は WSL では distro 名、Mac ではマシン名
- Starship が無ければ `./setup.sh` が入れる。入れられなければ理由と手順を出す
- シェルの設定ファイル(Mac は `~/.zshrc`、WSL は `~/.bashrc`)は置き換えず、必要な行を1回だけ足す。
  何度流しても増えない
- `starship.toml` は置かない

# Assumptions

- herdr の中ではタブのタイトルを herdr が決める(`ui.window_title`、既定 `{hostname}: {workspace}`)。
  `{terminal_title}` にするとスペースの多くで Claude Code の作業名が出て環境が分からないので、既定のままにする
  (2026-10-18 ユーザー判断)
- herdr の `{hostname}` は OS のホスト名なので、WSL では `/etc/wsl.conf` で各 distro のホスト名を distro 名にする。
  パスワード入力と distro の再起動が1回要る(2026-10-18 ユーザー判断)。distro 名は WSL が `$WSL_DISTRO_NAME` で渡す
- このMacのシェルは zsh、Starship 1.25.1 は Homebrew で導入済み。`~/.zshrc` には手で書いた
  `starship init zsh` が2行ある(確認済み)
- Windows 側は実機で確かめる必要がある(このMacからは確かめられない)

# Rules

- commit and push every change
- 会話・`.rn/` は日本語。コード・コミットメッセージ・PR は英語
- 過去セッションの `.rn/` 配下は読むだけで書き換えない
- README は、読み手が作業の結果から読み取れずに間違えることがあるときだけ変える
- レビューは目的に錨を下ろす。1人用 dotfiles。完了基準に照らして効かない指摘は挙げさせない

# Tasks

### #1: setup.sh で Starship とタブタイトルを入れる

**Purpose**: どの環境でも `./setup.sh` だけで、Starship のプロンプトと `<環境名>: <ディレクトリ>` のタブになる。

**Steps**:

- [x] Starship が無ければ入れる(Mac は Homebrew、WSL は公式インストーラ)
- [x] タイトルを出す処理を repo に置き、シェルの設定ファイルに読み込む行を1回だけ足す
- [x] このMacで流し、タイトルの出力と、2回目の実行で行が増えないことを確かめる
- [x] herdr の中のタブを確かめる(`{terminal_title}` を試し、既定に戻すと決めた)
- [x] WSL では `/etc/wsl.conf` のホスト名を distro 名にする
- [ ] Mac の iTerm2 だけのタブの表示をユーザーに確かめてもらう
- [ ] Windows(WSL)で同じことをユーザーに確かめてもらう

**Completion criteria**:

- Acceptance criteria の各項目を、Mac と WSL の実機で確かめている
