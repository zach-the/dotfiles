# ~/.bashrc

# Only run interactively
[[ $- != *i* ]] && return

# --- Path Exports ---
export PATH="$HOME/.local/bin:$PATH"
export TERM=xterm-256color

# --- History Settings ---
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=3000
HISTFILESIZE=10000
shopt -s checkwinsize
shopt -s direxpand

# --- Less / dircolors ---
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
if [ -x /usr/bin/dircolors ]; then
    eval "$(dircolors -b ~/.dircolors 2>/dev/null || dircolors -b)"
fi
export LESS="-XR"
export LESSCHARSET="utf-8"

# --- Prompt & Tab Title ---
# Only run this if the terminal supports colors and powerline-shell is installed
if command -v powerline-shell &>/dev/null && [[ $TERM != linux ]]; then
    function _update_ps1() {
        # 1. Generate the Powerline Prompt
        PS1=$(powerline-shell $?)
        
        # 2. Set the Ghostty Tab Title (Current Directory)
        # ${PWD/#$HOME/~} replaces /home/user with ~ to save space
        printf "\033]2;%s\007" "${PWD/#$HOME/~}"
    }

    # Append _update_ps1 to PROMPT_COMMAND if not already present
    if [[ ! "$PROMPT_COMMAND" =~ _update_ps1 ]]; then
        PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"
    fi
else
    # Fallback prompt (if powerline isn't installed)
    PS1='[\u@\h \W]\$ '
    
    # Fallback title setting
    case "$TERM" in
    xterm*|rxvt*|screen*|ghostty*)
        PROMPT_COMMAND='printf "\033]2;%s\007" "${PWD/#$HOME/~}"; '"$PROMPT_COMMAND"
        ;;
    esac
fi


# --- Key Bindings ---
bind 'TAB:menu-complete'
bind '"\e[Z":menu-complete-backward'
bind "set show-all-if-ambiguous on"
bind "set menu-complete-display-prefix on"
bind "set completion-ignore-case on"

# --- Time Zone Fix ---
export TZ='America/Denver'

[ -f ~/.bash_aliases ] && source ~/.bash_aliases
    
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

[ -f /home/zb900042/toolbox/setup/toolboxrc ] && source /home/zb900042/toolbox/setup/toolboxrc

[ -f ~/.local_aliases ] && source ~/.local_aliases

clear

