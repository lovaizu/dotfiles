Serves: goal

Windows Terminal で配色を Gruvbox Light に変えたとき、herdr の UI がいつ Light に揃えば足りますか。

分かったこと: iTerm2 は配色の明暗が変わると herdr に知らせるので、Change Profile した瞬間に herdr も
切り替わる見込みです。Windows Terminal はこの知らせを送らない(microsoft/terminal#18375 が未解決)ため、
配色を変えても herdr は前のテーマのままで、herdr に付け直したとき(detach して attach)に揃う見込みです
(付け直しで揃うかはまだ試していません)。

Windows で light に切り替える場面で、切り替えのあとに herdr を付け直す一手間があってもよいか、それとも
配色を変えたその場で herdr も揃っていてほしいかを教えてください。
