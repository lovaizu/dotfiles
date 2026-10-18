---
rn: 0.9.0
pr: https://github.com/lovaizu/dotfiles/pull/32
status: running
artifact-language: English
conversation-language: Japanese
readme: README.md
design: docs/design.md
verification: docs/verification.md
---

# Goal

Issue #19 を片付ける。Claude は Issue・PR・コミット・ドキュメントを白紙から書いていて、リポジトリに既にある同種のものの形(見出しとその順、言語、タイトルの書き方、根拠の量)に合うのはユーザーが言ったときだけ。
既にある集まりに1つ足す前に、そこにあるものを読み、その形で書く、を基本方針として `claude/CLAUDE.md` に書く。
既存の「リポジトリの言語で書く」の行はその一例になる。

# Acceptance criteria

## Attractive quality

- A1: 指示されなくても、Claude がこのリポジトリで新しい Issue を書くとき、既存の Issue を何件か(閉じたものも含め)読んでから `## Situation` / `## Desired State` の形・英語・命令形タイトルで書く
- A2: Issue 以外(PR 説明、コミットメッセージ、ドキュメント)でも、どのリポジトリでも同じ振る舞いになる

## Must-be quality

- M1: 追加は `claude/CLAUDE.md` の1か所にまとまり、手順やリポジトリ固有の事情を含まない(README の3層の基本方針に収まる)
- M2: 「Converse in Japanese」と「リポジトリの言語で書く、無ければ英語」の効き目は変わらない
- M3: 既存の例どうしが食い違うときは新しいほうに従い、集まりが使っていない節は作らない

# Assumptions

- Fact, `setup.sh` を読んで確認: `claude/CLAUDE.md` は `~/.claude/CLAUDE.md` に置かれ、全プロジェクトで読まれる
- Fact, Issue #19 本文: 置き場所は `claude/CLAUDE.md`(README の3層のうち基本方針)と Issue が決めている

# Rules

- リポジトリに残るもの(コード・コメント・コミット・PR 説明)は英語、会話と `.rn/` は日本語
- 過去セッションの `.rn/` は読むだけ
- `claude/CLAUDE.md` は短い行の箇条書き。行を足すより既存の言語の行を広げる
- README は変えない(3層の決め方は既に README にあり、読み手が取り違える点は増えない)
- レビュー指摘は目的に効くものに絞る。1人用 dotfiles

# Tasks

### [ ] #1: claude/CLAUDE.md に「既にある形に合わせる」を書く

Purpose: 言語の行を、既にある同種のものの形に合わせる一般の方針に広げる

Serves: A1, A2, M1, M2, M3

Completion criteria:

- Attractive quality: 新しい `claude/CLAUDE.md` だけを指示として渡した素の `claude -p` に、このリポジトリで Issue を1つ下書きさせると、既存の Issue を読んだうえで `## Situation` / `## Desired State` だけの英語の Issue を命令形のタイトルで出す
- Must-be quality: 変更は `claude/CLAUDE.md` の中だけで、会話の言語と英語既定の指示が残っている

### [ ] #2: Deliverable sign-off

# Not yet specified

- なし
