# 報告: plan(steering.md)の first user

## 読んだもの・使ったもの・見なかったもの

- 作品: `.rn/20261018-issue-15/steering.md`(全文。以下、行番号はこのファイルのもの)
- 観点: `rn/0.9.0/references/essentials/plan.md`、報告の形: `essentials/report.md`
- ユーザーが合意したもの: Issue #15 本文(`gh issue view 15 --repo lovaizu/dotfiles --json title,body,comments`。コメントは 0 件)
- plan が立つ事実を確かめるために見たもの:
  - リポジトリ: `README.md`、`herdr/config.toml`、`iterm2/herdr.json`、`windows-terminal/settings.json`、`setup.sh`、`lib/iterm2.sh`、`lib/windows_terminal.sh`、`lib/tools.sh`(herdr のインストール箇所のみ)、`.claude/rules/*.md`
  - このマシンで実行: `herdr --version`、`herdr --help`、herdr バイナリの `strings`、`defaults read /Applications/iTerm.app/Contents/Info.plist CFBundleShortVersionString`
  - 外部: `gh api` で microsoft/terminal#18375・#19904、gnachman/iTerm2 のタグ `v3.7.4` の `sources/PTYSession/PTYSession.m`、`sources/TerminalView/PTYTextView.m`、`sources/VT100/VT100Terminal.m`、`sources/VT100Screen/VT100ScreenMutableState.m`、`VT100ScreenMutableState+TerminalDelegate.m`(scratchpad に取得)
- 見なかったもの: コミット履歴とその差分、PR #31 の会話、過去セッションの `.rn/`、herdr のドキュメント(サイト)。herdr を起動して新しい設定を読ませること、iTerm2・Windows Terminal で実際に切り替えることはしていない(Windows 機はここにない)

---

## Reading the plan once, what did you take as the reason the user wants the goal?

作品からこう理解した: 理由は 2 つ(`steering.md:17-20`)。(1) いまは herdr だけが `gruvbox-light` で、選択行以外の UI が暗い背景の上で明るい背景向けの色で描かれ、未選択の Space 名が 1.67:1 で読みにくい。`active_row_bg` ができたので UI 全体を反転させなくても選択を見分けられる。(2) light で作業できる道がどちらの機械にもない。

Issue と並べると、(1) は Issue の Situation(「The cost is everything else ... 1.67:1 ... separators are near-white lines on dark」)と一致する。(2) について plan は「明るい環境で作業したいときに」(`steering.md:20`)と書くが、Issue が書くのは「there is no way to work in light on either machine」までで、明るい環境という場面は Issue にない。

## Reading the attractive criteria beside the reason the user wants the goal, what of that reason do they leave out?

作品からこう理解した:
- Goal の一文目「herdr の UI テーマをターミナルと同じ Gruvbox の明暗に揃え」(`steering.md:14`)、Issue の「The terminal and herdr use the same Gruvbox variant」のうち、Dark 側で herdr がターミナルと同じ Dark に揃うことを A1(`steering.md:26-27`)は言っていない。A1 は「読め」「見分けられる」だけで、揃うと言うのは A2 の Light 側(`steering.md:29`)だけ。
- A1 の「読め」には基準がない。Issue は読みやすさを比で言っている(未選択名 1.67:1 が問題、選択行の名前 6.43:1 / 6.76:1)。plan の Goal は 1.67:1 を問題として挙げる(`steering.md:18-19`)が、A1 で何が満たされれば「読める」かは書かれていない。
- 理由 (2) は A2 が受けている。理由 (1) の「UI 全体を反転させずに選択を見分けられる」は A1 の後半が受けている。

## Reading each attractive criterion beside what the user said, which of what it says they gain did the user not say?

作品からこう理解した:
- A2 の「Windows Terminal では herdr に付け直す(detach して attach)と追従する」(`steering.md:30`)。Issue が言うのは「Worth confirming while implementing: whether iTerm2 and Windows Terminal actually emit the color-scheme change notification ... If they do not, herdr keeps its current theme until it is reattached.」で、確かめるべき点とその場合の帰結として書かれている。付け直せば追従することをユーザーが得たいものとして述べた箇所は Issue にない。plan 自身も、付け直しで追従するかは Assumption で未検証としている(`steering.md:58-59`)。
- A2 の「iTerm2 では herdr がその場で追従し」も、Issue では上と同じ「確かめる」の側にあり、ユーザーが選んだ利得としては書かれていない(Issue の herdr 箇条にある「switched its UI live」は 0.8.2 に通知を送った検証結果)。
- A2 の「Dark に戻すのも同じ操作でできる」は Issue に文としてはない。Issue の「Both variants are usable ... switched by hand in the terminal」から読める範囲。
- A1 の項目(未選択の Space 名・区切り線、Space / Agent 行)は Issue の Situation / Desired State にある。

## Checking each fact the plan rests on at its source, which did not hold?

書かれたとおりに確かめたら、こうなった:
- `steering.md:42-43` herdr 0.9.1: `herdr --version` が `herdr 0.9.1` を出した(`/Users/kiyo/.local/bin/herdr`)。バイナリの strings に `active_row_bg`、`# [theme.custom.light]`、`# [theme.custom.dark]`、`# Layer appearance-specific overrides on top when auto_switch is enabled.` がある。成り立った。
- `steering.md:44-45` Windows Terminal: 両スキームが定義済みなのは成り立った(`windows-terminal/settings.json:272` `Gruvbox Dark`、`:295` `Gruvbox Light`)。「既定プロファイルは `Gruvbox Dark`」は成り立たなかった。`defaultProfile` は `{61c54bbd-...}`(`settings.json:41`)で、これは `Windows PowerShell`(`:103-105`)。`Gruvbox Dark` は `profiles.defaults.colorScheme`(`:92`)で、`list` の 6 プロファイル(`:101-136`)はどれも `colorScheme` を上書きしていない(`grep -n colorScheme` の結果は `:92` の 1 件だけ)。
- `steering.md:46-49` Issue からの 2 件: Issue 本文に同じ記述がある。成り立った。
- `steering.md:50-52` iTerm2: タグ `v3.7.4` で、`PTYSession.m:13979-13997` の `textViewBackgroundColorDidChangeFrom:to:` は `before.isDark != after.isDark` のとき `notifyTerminalOfDarknessChange` を呼ぶ。呼び出し元は `PTYTextView.m:6414-6419` の color map デリゲートで、`kColorMapBackground` の変化すべてで呼ばれる。`VT100ScreenMutableState.m` の `darknessDidChange` は `sendUnsolicitedDarkModeDSR` のときに送る。これは `VT100Terminal.m:996-998` で mode 2031 が立てる。送る値は `VT100Terminal.m:1377-1379` で `CSI ? 997 ; 1|2 n`。明暗は `VT100ScreenMutableState+TerminalDelegate.m:4110-4114` で背景色から判定している。このマシンの iTerm2 は 3.7.4。成り立った。Change Profile が背景色の color map を書き換える経路そのものは追っていない。
- `steering.md:53-55` microsoft/terminal#18375: `state: open`、題は「Implement (Contour's) Color Palette Update Notification and report」。成り立った。同じ箇条の「手動でスキームを変えても herdr は前のテーマのまま」は、この issue からの推論で、観察した結果ではない。「Issue #15 はこの場合『付け直すまで前のテーマ』を受け入れている」は、Issue では「Worth confirming ... If they do not, herdr keeps its current theme until it is reattached.」と書かれている(受け入れと読むかどうかは次の観点の 2 つ下を参照)。
- `steering.md:56-57` #19904: 題は「Terminal background color response (OSC 11) leaks into prompt in Windows Terminal and Warp」(closed)。Windows Terminal が OSC 11 に答えることは、この題と本文から読める。WSL 内のプロセスへ応答が届くかは、この issue からは分からない。
- `steering.md:58-59` Assumption: バイナリに `]11;?` があることを確かめた。あわせて `[?2031h`、`[?2031l`、`[?997;1n`、`[?997;2n` もある。

## Acting on the plan, which fact you relied on can neither the repository nor any documentation show, yet is recorded neither as told by the user nor as an Assumption?

作品からこう理解した:
- Windows 機の herdr のバージョン。plan の事実は「このマシン」(Mac)の 0.9.1 だけ(`steering.md:42`)。`herdr/config.toml` は両機に配置される共通ファイル(`setup.sh:52`)で、Issue は 0.8.2 が `[theme.custom.light]` を `unknown config key` で拒むと書いている。`lib/tools.sh:12-13` は herdr が入っていれば何もしないので、`./setup.sh` を流しても Windows 側の herdr は新しくならない。Windows 機に何が入っているかはリポジトリにもドキュメントにもなく、ユーザーから聞いた事実としても Assumption としても書かれていない。
- Windows Terminal のバージョンと、WSL の中で動く herdr へ OSC 11 の応答が届くか。A2 の Windows 側(`steering.md:30`)はこれに立つ。plan は「付け直しで追従するかは未検証」(`steering.md:59`)とまとめて Assumption にしているが、WSL を通ることは書かれていない。
- iTerm2 で Change Profile をどこから操作するか(メニュー、キー、どのセッションに効くか)。A2 は「ターミナル側の手動操作だけで」と言い、Issue は「the session switches between them through Change Profile」と書くが、plan にはその操作が実際にあるかの事実も Assumption もない。

## Reading the criteria, which kind of input they speak of, such as "a user with no name", has forms where the product runs that neither the repository shows nor the user told, or was tried today on only some of its forms?

作品からこう理解した。今日は切り替えをどの形でも試していない(`steering.md:82` の Not yet specified の最後の項目が「実機で確かめる」)。基準が言う「ターミナル側の手動操作」(`steering.md:28`)には、次の形がある。
- Windows Terminal: 設定画面で変えるのは、プロファイルごとの配色か、全プロファイルが継承する `defaults` の配色(`settings.json:92`、`:101-136`)。そのほかに、保存せずに今のタブだけ変えるコマンドパレットの配色変更がある(これは私の Windows Terminal の知識で、リポジトリにはない)。設定画面で変えると、`./setup.sh` が配置する `settings.json` そのものが書き換わる(`lib/windows_terminal.sh` は LocalState の `settings.json` に配置する)。どの形を指すのかを基準は言っていない。
- iTerm2: Change Profile はセッション(ペイン)ごとに効く。ウィンドウやタブが複数あるとき、herdr を動かしていないセッションがどうなるかを基準は言っていない。
- herdr の付け直し: 同じ herdr セッションに複数のクライアントが付くとき(例えば `herdr --remote`、`herdr session attach`。`herdr --help` に出る)、テーマがクライアントごとかサーバー全体かは、リポジトリにも plan にもない。

## Acting on the plan, which point you relied on is a decision only the user can make, yet is not recorded as theirs?

作品からこう理解した:
- Windows Terminal では付け直すまで herdr が前のテーマのままでよいこと。plan はこれを Issue が「受け入れている」と書き(`steering.md:54-55`)、A2 に入れている(`steering.md:30`)。Issue の該当文は「Worth confirming while implementing」の段落にあり、受け入れると決めた言葉ではない。
- README に、light への切り替え方や 2 つ目の iTerm2 プロファイルの意図を書くか書かないか。plan は消すことだけを書く(M4 `steering.md:38`、Not yet specified)。`.claude/rules/readme.md` は書く前に問うよう求めているが、誰がどう決めたかは plan に書かれていない。
- iTerm2 の 2 つ目のプロファイルが setup.sh の既定プロファイル確認(`lib/iterm2.sh:13-26`)とどう関わるか(Light のウィンドウを既定にしたら警告が出るなど)。Issue は「Making it stick on Mac would mean changing iTerm2's default profile ... not worth the complexity」までをユーザーが決めている。M2 はこれに沿っている。
- M1・M3・選択行の色は、Issue の「The choice is not persisted, by design」「The OS appearance setting stays at its default and is not involved」、色の指定に対応しており、ユーザーの言葉がある。

## Following the tasks in order, which acceptance criterion did no task bring to hold?

作品からこう理解した: Tasks は `#1: Plan sign-off` と `#2: Design sign-off` だけ(`steering.md:73-74`)。成果物を作るタスクはまだ計画されていないので、観点ファイルの指示(「Before the tasks that make the deliverable are planned, the questions on tasks are not asked」)に従い、この問いは扱わない。

## Reading a task's Completion criteria as its generator, what of the task's purpose toward the attractive criteria do they leave out?

作品からこう理解した: 同じ理由で扱わない。2 つのタスクには Completion criteria の記述がない(`steering.md:73-74`)。

## Following the tasks in order, which work on must-be quality comes before the attractive criteria are nearly met?

作品からこう理解した: 同じ理由で扱わない。参考までに、Not yet specified の並び(`steering.md:76-82`)は herdr 設定 → iTerm2 プロファイル → README 削除(M4) → 実機確認(A2 の追従)の順で、A2 の追従を確かめるのが最後に来ている。

## Carrying the work on from the plan, which parts did you use and which did you pass over?

作品からこう理解した:
- 使った部分: Goal(`:12-20`)、Acceptance criteria(`:22-38`)、Assumptions(`:40-59`)。どれも上の各観点で事実を確かめたり、Issue と並べたりするのに使った。Not yet specified(`:76-82`)は、残っている作業と順序を知るのに使った。
- 読み流した部分: Rules(`:61-69`)。すべて `.claude/rules/*.md` とセッション運用の繰り返しで、この plan を進める判断には使わなかった。Front matter のうち `readme` / `design` / `verification` のパス(`:7-9`)は、指す先(`docs/design.md`、`docs/verification.md`)がリポジトリにまだない(`git ls-files` に出ない)ので使っていない。Tasks(`:71-74`)はサインオフの 2 行だけで、作業の手がかりにはならなかった。

---

## Conductor: Good / More

- Good A1: 未選択の Space 名・区切り線という、Issue が挙げた読みにくさの箇所をそのまま受けている(steering.md:26-27)
- Good A2: 両ターミナルで手動で切り替えるという Issue の望む状態を受けている(steering.md:28-30)
- Good M1: 保存しないことと setup.sh が Dark を基準に置くことが Issue の言葉どおり(steering.md:35)
- More A1: Dark で herdr がターミナルと同じ Dark に揃うことを言っておらず、「読め」に目安がない(steering.md:26-27)
- More A2: 「iTerm2 はその場で」「WT は付け直すと」はユーザーが選んだ利得ではなく、確かめる点として Issue にある(steering.md:29-30)
- More A2: 明るい環境という場面は Issue にない(steering.md:20)
- More A2: WT の既定プロファイルが Gruvbox Dark という事実は誤り。Gruvbox Dark は profiles.defaults の配色(steering.md:44-45)
- More A2: Windows 機の herdr が 0.9.0 以上かが事実にも Assumption にもない(steering.md:42-43)
- More A2: WT で付け直すまで前のテーマでよいことがユーザーの決定として記録されていない(steering.md:54-55)
- More A2: WT の手動切り替えの形(設定画面・一時変更)、iTerm2 の Change Profile の操作が記録にない
- More M4: README に切り替え方を書くかの扱いがない(steering.md:38)
- More M2: 同じ herdr に複数クライアントが付くときのテーマの扱いが記録にない
