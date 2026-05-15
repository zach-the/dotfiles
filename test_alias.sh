shopt -s expand_aliases
alias testalias="tmp=foo && history -d -1 && history -s \"nvim \$tmp\" && echo \$tmp"
testalias
history | tail -n 3
