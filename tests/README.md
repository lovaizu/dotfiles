# tests

`lib/merge.py` の回帰スイートとファズ。`setup.sh` が設定ファイルを**項目マージ**する部分
(dotfiles が持つキーだけを置き換え、配置先にしか無いキーは残す)を対象にする。

## 走らせ方

```sh
cd tests
python3.12 suite.py          # 回帰スイート
python3.12 fuzzrand.py       # ランダムに組み立てた valid TOML でのファズ
python3.12 fuzzmut.py        # 実 herdr config の 1 バイト変異ファズ(数分かかる)
bash realdata.sh             # 実ファイルのコピーに対する往復
```

**オラクルに python 3.12 以上が要る**(`tomllib` を使って「出力が有効な TOML か」を判定するため)。
マージ本体はそれとは別で、既定では `/usr/bin/python3`(mac 同梱の 3.9)に投げる — `lib/merge.py` が
3.9 で動くことが要件なので、オラクルと本体をわざと別の実装に分けている。本体を別の python で
試すときは `MERGE_PY=/path/to/python3` を渡す。

`realdata.sh` は `~/.config/herdr/config.toml` と `~/.claude/settings.json` を**コピーしか触らない**。
実ファイルの md5 と mtime を前後で表示して突き合わせるので、触っていないことがその場で確認できる。
Claude Code のコピーには、そのマシンにしか無い材料(独自キー・dotfiles に無いイベント・dotfiles と
同じ matcher の下の独自フック)を足してからマージする — 実ファイルは既に dotfiles と同じ内容なので、
そのまま流しても何も確かめられないため。
各マージが実際に走ったか・値が期待どおりかを1件ずつ検査し、1つでも外れたら `REALDATA: FAIL (n)` と
出して終了コード 1 で終わる(以前は何も走らなくても成功と読める出力を出していた)。
herdr の検査は `XDG_CONFIG_HOME` を差し替えて `herdr config check` に読ませる
(`herdr config check` は位置引数を取らない)。

## 何を保証しているか

- **有効だった配置先が無効になって返ることはない。** 元から不正だった配置先が「マージした」で
  返り不正なままであることは許容する — 値の綴りは検査せず、不正ならアプリ自身が言う
- 配置先にしか無いキーが残る。**コメント・行順・改行コードが残るのは TOML だけ** — JSON は
  文書を組み直して書き出すので、JSONC のコメントは落ち(マージが警告する)、改行は元が CRLF でも
  常に LF になる(こちらは警告しない)
- アプリ自身が要素を書き足す配列(WT の `profiles.list` / `actions` / `schemes`、
  Claude Code の `hooks.<Event>` と、その要素の中の `hooks`)は id で1件ずつ突き合わせ、
  そのマシンにしか無い要素が残る
- 冪等 — 2 回流しても同じバイト列
