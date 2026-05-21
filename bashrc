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
set -o vi
set -show-mode-in-prompt on
set vi-ins-mode-string \1\e[6 q\2
set vi-cmd-mode-string \1\e[2 q\2

# Enable vi editing mode
set editing-mode vi
set show-mode-in-prompt on

# Insert Mode (Green block -> Green arrow on Dark Grey background)
set vi-ins-mode-string "\1\e[42;30m\2 I \1\e[100;32m\2\1\e[0m\2"

# Normal/Command Mode (Blue block -> Blue arrow on Dark Grey background)
set vi-cmd-mode-string "\1\e[44;30m\2 N \1\e[100;34m\2\1\e[0m\2"



export EDITOR='nvim'
export VISUAL='nvim'

# --- Time Zone Fix ---
export TZ='America/Denver'

[ -f ~/.bash_aliases ] && source ~/.bash_aliases
    
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

[ -f /home/zb900042/.zachs_toolbox_sandbox_aliases ] && source /home/zb900042/.zachs_toolbox_sandbox_aliases

[ -f ~/.local_aliases ] && source ~/.local_aliases

clear

# Function to keep track of directory changes
_track_dir_change() {
    # Initialize if empty
    if [[ -z "${_DIR_HISTORY[*]}" ]]; then
        _DIR_HISTORY=("$PWD")
        _DIR_HISTORY_INDEX=0
    fi

    local hist_dir="${_DIR_HISTORY[$_DIR_HISTORY_INDEX]}"

    if [[ "$PWD" != "$hist_dir" ]]; then
        # A new directory change occurred! Truncate forward history
        _DIR_HISTORY=("${_DIR_HISTORY[@]:0:$((_DIR_HISTORY_INDEX + 1))}")
        
        # Add new directory
        _DIR_HISTORY+=("$PWD")
        ((_DIR_HISTORY_INDEX++))
        
        # Limit history size to 100 to prevent unbounded growth
        if (( ${#_DIR_HISTORY[@]} > 100 )); then
            _DIR_HISTORY=("${_DIR_HISTORY[@]:1}")
            ((_DIR_HISTORY_INDEX--))
        fi
    fi
}

# Append our tracking function to PROMPT_COMMAND safely
if [[ -z "$PROMPT_COMMAND" ]]; then
    PROMPT_COMMAND="_track_dir_change"
else
    if [[ "$PROMPT_COMMAND" != *"_track_dir_change"* ]]; then
        PROMPT_COMMAND="_track_dir_change; $PROMPT_COMMAND"
    fi
fi
