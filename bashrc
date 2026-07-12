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
_lsf_parse_file() {
    local found_header=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        local clean="${line#"${line%%[^[:space:]]*}"}"  # strip leading whitespace
        clean="${clean%"${clean##*[^[:space:]]}"}"       # strip trailing whitespace
        if [[ "$found_header" -eq 0 ]]; then
            [[ "$clean" == *ClusterName* && "$clean" == *Servers* ]] && found_header=1
        else
            [[ -z "$clean" || "$clean" == '#'* ]] && continue
            read -r name _ <<< "$clean" && echo "$name"  # first word, splits on any whitespace
            return
        fi
    done < "$1" 2>/dev/null
}

_lsf_cluster_name() {
    local envdir="${LSF_ENVDIR:-}"
    [[ -z "$envdir" || ! -d "$envdir" ]] && return

    local name standard="$envdir/lsf.shared"
    [[ -f "$standard" ]] && name=$(_lsf_parse_file "$standard")

    if [[ -z "$name" ]]; then
        local f
        for f in "$envdir"/*; do
            [[ "$f" == "$standard" || ! -f "$f" ]] && continue
            name=$(_lsf_parse_file "$f")
            [[ -n "$name" ]] && break
        done
    fi
    echo "$name"
}

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
    local c_lsf=$bred
    local c_gev=$cyn
    local c_block=$mag
    local c_pwd=$blu
    local c_git=$grn

    local p=''

    if [[ -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
        p+="${c_ssh}[SSH]${reset}"
    fi

    local lsf_cluster
    lsf_cluster=$(_lsf_cluster_name)
    if [[ -n "$lsf_cluster" ]]; then
        p+="${c_lsf}[${lsf_cluster}]${reset}"
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
    printf "\033]2;%s\007" "${PWD/#$HOME/~}"
    _ascii_prompt
}

if [[ ! "$PROMPT_COMMAND" =~ _update_ps1 ]]; then
    PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"
fi

export EDITOR='nvim'
export VISUAL='nvim'

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
