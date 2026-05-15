shopt -s expand_aliases
alias fzv='tmp="my file.txt" && history -s "nvim \"$tmp\"" && echo "$tmp" && echo nvim "$tmp"'
fzv
history | tail -n 2
