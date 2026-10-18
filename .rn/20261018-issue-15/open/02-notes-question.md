Serves: goal

Windows Terminal で配色を Gruvbox Light に変えたとき、herdr の UI がいつ Light に揃えば足りますか。

分かったこと: iTerm2 は配色の明暗が変わると herdr に知らせるので、Change Profile した瞬間に herdr も
切り替わる見込みです。Windows Terminal はこの知らせを送らない(microsoft/terminal#18375 が未解決)ため、
配色を変えても herdr は前のテーマのままです。Windows Terminal 側が対応するまで、その場で揃える手段は
このリポジトリの設定では作れません。

代わりに、herdr に付け直す(`ctrl+t` `q` で detach し、もう一度 `herdr` を起動して attach)と揃う見込み
です。まだ試していないので、計画が決まったら実機で確かめます。付け直しで揃わなければ、Windows で
light を使う方法をもう一度あなたと相談します。

Windows で light に切り替える場面で、切り替えのあとに herdr を付け直す一手間があってもよいか、それとも
配色を変えたその場で herdr も揃っていなければ light を使う意味がないかを教えてください。
