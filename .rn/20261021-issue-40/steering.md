# Goal

Windows で、WSL の `~/work/<group>` の下から `sb` を起動すると、Mac と同じように、そのグループの sandbox の中で herdr が開く(Issue #40)。
あわせて Windows の小さな直しを同じ PR に入れる(ユーザー判断): Windows Terminal で範囲選択したらコピー(Issue #42)、`./setup.sh` の文字化け。

# Acceptance criteria

- 新しいマシンでも `./setup.sh` を1回流せば sb が使える。手作業が要るなら `./setup.sh` か sbx・Claude がその場で言う
- sandbox の中で、Mac と同じく、ホストと同じパスでグループが見え、worktree の git も通り、速さが作業に耐える
- GitHub のトークンは gh のログインから取る。gh がログインしていなければ「ログインして」と言って止まる(ユーザー判断)
- Windows Terminal で範囲選択するとコピーされる(herdr なしでも)。`./setup.sh` に文字化けが出ない

# Assumptions

- このPCは会社のPC。GitHub は kiyohome で作業する。kiyobot は個人PCだけ(ユーザー)
- Windows 11 Pro、Intel Core Ultra 7 265H、WSL は Ubuntu 24.04(distro 名 my)。`/dev/kvm` あり(root:kvm)、ユーザーは kvm グループに入っていない
- gh は WSL で kiyohome にブラウザでログイン済み(`~/.config/gh/hosts.yml`)
- iTerm2 は既定で選択をコピーする。この repo は触っていない(Mac では未確認)
- **前提の誤り(2026-10-21、ユーザー指摘)**: #24 で試さず決めた「WSL から Windows の `sbx.exe` を interop で呼ぶ」は、
  「Windows では作業は WSL の中」という repo の前提に反する。Windows 版で試して分かったこと:
  - winget で WSL から入る(管理者不要、`%LOCALAPPDATA%\DockerSandboxes\bin`)。入れた直後の WSL の PATH には出ない
  - kit は `\\wsl.localhost\...` のまま読めた。1回目の作成は `500 ... failed to cache durable-startup payload` で失敗、作り直すと通った(原因不明)
  - グループは VM の中で `/wsl.localhost/my/home/...` にマウントされる。herdr のペインは `/home/agent` で開いた
  - ホストで作った worktree は中で `fatal: not a git repository`(`.git` がホストのパスを指す)
  - 中では全ファイルが 777 に見え、git が全ファイルを mode change と言う
  - 中の `git status` が ccpm(177ファイル)で 2〜4 秒(ホストは 0.003 秒)。starship が時間切れの警告を出す
  - どれも Windows を経由する遠回りが原因。Linux 版 sbx を WSL の中で動かせば避けられる見込み(未確認)
- Linux 版 sbx の条件(公式): Ubuntu 24.04 以降、KVM、ユーザーが kvm グループ。VM の中なら nested virtualization

# Rules

- 会話・`.rn/` は日本語。コード・コミットメッセージ・PR は英語
- 決めることはユーザーに1つずつ聞く
- 作業はクローンでブランチ `issue-40`(worktree にしない。`./setup.sh` がこのクローンを適用するため。ユーザー判断)。マージ後は `main` に戻す
- PR は sb が WSL で動くのを確かめてから。`Closes #40`、`Closes #42`
- 前提(WSL の中で作業)に沿って決める。Windows 側を経由する案は、その理由を確かめてから

# Tasks

### #1: Linux 版 sbx が WSL の中で動くか小さく試す

**Steps**:

- [ ] ユーザーの了承を取る(kvm グループに入れる sudo、Linux 版 sbx を入れる)
- [ ] Linux 版を入れ、グループをマウントした sandbox を作る。見ること: 動くか、パスがホストと同じか、worktree の git、mode、速さ
- [ ] 動けば、Windows 版の処理(winget、`~/.local/bin/sbx.exe` のリンク、`sb` と run_after の `sbx.exe`)を Linux 版に置き換える。
  Windows 側の sbx と sandbox `lovaizu` の片付けも

### 済み(ブランチ `issue-40`、コミット cb5bf4f、未 push)

- Windows Terminal の `copyOnSelect` を true(コピーできたかはユーザー未回答)
- `cmd.exe` を `cd /mnt/c` してから呼び、文字化けを消した(確認済み)
- GitHub トークンを `gh auth token` から sbx に渡す(確認済み)。Windows 版前提の部分は #1 の結果で書き直す
- Windows 版 sbx の winget インストールとリンク(確認済み、ただし #1 次第で捨てる)
