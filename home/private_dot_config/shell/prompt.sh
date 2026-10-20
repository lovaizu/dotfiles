# Sourced from ~/.zshrc or ~/.bashrc by the one line chezmoi adds there.

command -v starship >/dev/null 2>&1 || return 0

# The distros of one PC all share its hostname, so on WSL the distro name is
# what tells their tabs apart.
_prompt_host="${WSL_DISTRO_NAME:-$(hostname -s)}"

# The tab shows the host instead of the prompt. herdr replaces this title
# with its own "<hostname>: <workspace>", which is why run_after_wsl-hostname.sh
# gives each distro its name as hostname too.
_prompt_title() {
  # Through a variable: a quoted or escaped ~ keeps its backslash in zsh and
  # bash 3.2 (measured).
  local tilde='~'
  printf '\033]0;%s: %s\007' "$_prompt_host" "${PWD/#"$HOME"/$tilde}"
}

# Starship's user hook is bash-only and takes a function name; zsh has its
# own precmd list (read in starship 1.25's init scripts).
if [ -n "${ZSH_VERSION:-}" ]; then
  precmd_functions+=(_prompt_title)
  eval "$(starship init zsh)"
else
  starship_precmd_user_func=_prompt_title
  eval "$(starship init bash)"
fi
