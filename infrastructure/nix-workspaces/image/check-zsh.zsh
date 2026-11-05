# Run through an interactive login shell: zsh -lic "$(cat check-zsh.zsh)".
set -eu
[[ -o interactive && -o login ]]
[[ "$SHELL" == /opt/tools/bin/zsh ]]
[[ "$EDITOR" == nvim ]]
[[ "$STARSHIP_CONFIG" == "$HOME/.config/starship/starship.toml" ]]
[[ -r "$STARSHIP_CONFIG" ]]
[[ "$aliases[vim]" == nvim && "$aliases[c]" == clear ]]
[[ "$HISTSIZE" == 5000 && "$SAVEHIST" == 5000 ]]
[[ -o sharehistory && -o histignoredups ]]
(( $+functions[compdef] && $+functions[fzf-tab-complete] ))
(( $+functions[_zsh_autosuggest_start] && $+functions[_zsh_highlight] ))
(( $+functions[__zoxide_z] && $+functions[prompt_starship_precmd] ))
[[ "$(bindkey '^p')" == *history-search-backward* ]]
for tool in zsh starship zoxide fzf nvim git; do
  command -v "$tool"
done
zsh --version
print 'PASS: shared Zsh login, completion, suggestions, highlighting, aliases, history, zoxide, and Starship'
