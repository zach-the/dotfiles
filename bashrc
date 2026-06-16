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
# Set PROMPT_STYLE="ascii" to use the ASCII prompt; default uses powerline-shell.
# Toggle live with: PROMPT_STYLE=ascii  or  PROMPT_STYLE=powerline
PROMPT_STYLE="${PROMPT_STYLE:-ascii}"

_ascii_prompt() {
    # --- color bank ---
    local reset='\[\e[0m\]'
    # normal (dim) fg
    local blk='\[\e[30m\]'
    local red='\[\e[31m\]'
    local grn='\[\e[32m\]'
    local yel='\[\e[33m\]'
    local blu='\[\e[34m\]'
    local mag='\[\e[35m\]'
    local cyn='\[\e[36m\]'
    local wht='\[\e[37m\]'
    # bright fg
    local bblk='\[\e[90m\]'
    local bred='\[\e[91m\]'
    local bgrn='\[\e[92m\]'
    local byel='\[\e[93m\]'
    local bblu='\[\e[94m\]'
    local bmag='\[\e[95m\]'
    local bcyn='\[\e[96m\]'
    local bwht='\[\e[97m\]'
    # --- segment colors (edit these) ---
    local c_venv=$grn
    local c_ssh=$yel
    local c_user=$bwht
    local c_gev=$bblu
    local c_block=$bcyn
    local c_pwd=$mag
    local c_git=$grn

    local p=''

    if [[ -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
        p+="${c_ssh}[SSH]${reset}"
    fi

    if [[ -n "$VIRTUAL_ENV" ]]; then
        p+="${c_venv}($(basename "$VIRTUAL_ENV"))${reset}"
    fi

    if [[ -n "$MY_BLOCK" ]]; then
        p+="${c_block}[${MY_BLOCK}]${reset}"
    fi

    if [[ -n "$GEV_CHAR_MODE" ]]; then
        p+="${c_gev}[${GEV_CHAR_MODE}]${reset}"
    fi

    # p+="${c_user}[\u : ${reset}"

    local resolved_pwd
    resolved_pwd=$(pwd -P)
    resolved_pwd="${resolved_pwd/#$HOME/~}"
    p+="${c_pwd}[${resolved_pwd}]${reset}"

    local branch
    branch=$(git branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        local dirty=''
        git diff --quiet 2>/dev/null || dirty='*'
        git diff --cached --quiet 2>/dev/null || dirty='*'
        [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]] && dirty='*'

        local ahead='' behind=''
        local ahead_n behind_n
        ahead_n=$(git rev-list @{u}..HEAD --count 2>/dev/null)
        behind_n=$(git rev-list HEAD..@{u} --count 2>/dev/null)
        [[ "$ahead_n" -gt 0 ]] 2>/dev/null && ahead="+${ahead_n}"
        [[ "$behind_n" -gt 0 ]] 2>/dev/null && behind="-${behind_n}"

        local git_body="${c_git}${branch}${reset}"
        [[ -n "$dirty"  ]] && git_body+="${yel}${dirty}${reset}"
        [[ -n "$ahead"  ]] && git_body+="${grn}${ahead}${reset}"
        [[ -n "$behind" ]] && git_body+="${red}${behind}${reset}"
        p+="${c_git}(${git_body}${c_git})${reset}"
    fi

    p+='\n\$ '
    PS1="$p"
}

_update_ps1() {
    local exit_code=$?
    printf "\033]2;%s\007" "${PWD/#$HOME/~}"
    if [[ "$PROMPT_STYLE" == "ascii" ]] || ! command -v powerline-shell &>/dev/null || [[ $TERM == linux ]]; then
        _ascii_prompt
    else
        PS1=$(powerline-shell $exit_code)
    fi
}

if [[ ! "$PROMPT_COMMAND" =~ _update_ps1 ]]; then
    PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"
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
export PATH=$HOME/.npm-global/bin:$PATH
