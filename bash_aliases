# --- Aliases ---
alias sudo='sudo '
alias ls='ls --color=auto'
alias grep='grep --color=auto'
# alias zg='rg -z'
# alias rgs='rg -S'
# alias zgs='rg -z -S'
alias rg='rg -zS'
alias df='tmp=$(fd --type d -d 4 | fzf) && history -s "d \"$tmp\"" && echo "$tmp" && d "$tmp"'
alias e='clear && exit'
alias ll='ls -lrth'
alias wcl='wc -l'
alias l='ls -lh'
alias la='ls -lah'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history | tail -n1 | sed -e "s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//")"'
alias py='python3'
alias lns='ln -s'
alias tl='~/dotfiles/bin/tl'
alias cp='cp -a'
alias lg='ls -lrgah | rg -i'
alias nvs='nv -O'
alias nvr='nv -R'
#proc nvg = open all files that match a grep input in split view
#proc nvf = open all files that matcha fzf input in a split view
alias work='autossh -M 0 -t zb900042@lvnvda8240.lvn.broadcom.net "LAUNCH_NEW_TMUX=true exec bash -l"'
alias color_test='for i in {0..7}; do printf "\e[48;5;${i}m  "; done; printf "\e[0m\n"; for i in {8..15}; do printf "\e[48;5;${i}m  "; done; printf "\e[0m\n"'
alias zd='~/dotfiles/bin/zd -vw'
alias audio-combine='~/dotfiles/bin/audio-combine'
alias pp='realpath'
alias rs='rsync -aHAX --info=progress2'

# tmux session manager/attaching
tm() {
    local new_label="  [new session]"
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -vE '^.+-[0-9]{10}$')

    _tm_create() {
        local name="$1"
        if [[ -n "$TMUX" ]]; then
            tmux new-session -d -s "$name" 2>/dev/null || true
            tmux switch-client -t "$name"
        elif [[ -n "$name" ]]; then
            tmux new-session -s "$name"
        else
            tmux new-session
        fi
    }

    local choice
    if [[ -z "$sessions" ]]; then
        # No sessions exist — skip fzf and just create one
        clear
        read -p "session name: " new_session_name
        _tm_create "$new_session_name"
        return
    fi

    # Format numeric session names as "session #N" for display
    local display
    display=$(printf '%s\n' "$sessions" | sed 's/^[0-9][0-9]*$/session #&/')

    choice=$(printf "%s\n%s" "$display" "$new_label" | fzf --prompt="tmux> ")
    [[ -z "$choice" ]] && return

    if [[ "$choice" == "$new_label" ]]; then
        clear
        read -p "session name: " new_session_name
        _tm_create "$new_session_name"
    else
        # Reverse display label back to actual session name
        local session_name="$choice"
        [[ "$choice" =~ ^session\ #([0-9]+)$ ]] && session_name="${BASH_REMATCH[1]}"
        
        # Create a new grouped session with a unique name based on time
        # This allows multiple terminals to view different windows independently.
        # Clean it up on detach via a client-detached hook rather than the
        # destroy-unattached option: that option is checked immediately when
        # set, and this new session has zero attached clients until the
        # new-session call above finishes handing off this client to it --
        # setting destroy-unattached in that window destroys the session
        # (and any option set on it, like @protected below) before it's ever
        # used. A hook only fires on a real future detach, so it's race-free.
        local group_session="${session_name}-$(date +%s)"
        local parent_protected
        parent_protected=$(tmux show-options -t "$session_name" -v @protected 2>/dev/null)
        tmux new-session -t "$session_name" -s "$group_session" \; set-hook -t "$group_session" client-detached "kill-session -t \"$group_session\"" \; set-option -t "$group_session" @protected "${parent_protected:-0}"
    fi
}

# safe nvim (any file over 200mb uses a stripped-down nvim; over 1.5gb uses less/zless)
# nvs/nvr are aliases to this function, so they inherit the same behavior.
nv() {
    # 1. No arguments? Just open nvim.
    if [ "$#" -eq 0 ]; then
        command nvim
        return
    fi

    local normal_limit_mb=200
    local hard_limit_mb=1536 # 1.5gb
    local normal_limit_bytes=$((normal_limit_mb * 1024 * 1024))
    local hard_limit_bytes=$((hard_limit_mb * 1024 * 1024))

    local max_size_bytes=0
    local any_medium=false
    local any_large=false
    local file_report=""

    # Variables to cache single-file data so we don't recalculate later
    local single_human_size=""
    local single_is_gz=false

    # 2. Pre-check all provided files
    for file in "$@"; do
        if [ -f "$file" ]; then
            local size_bytes=0
            local is_gz=false

            if [[ "$file" == *.gz ]]; then
                # Get uncompressed size from gzip header
                size_bytes=$(gzip -l "$file" | tail -n 1 | awk '{print $2}')
                is_gz=true
            else
                # Portable stat for macOS and Linux
                if stat --version >/dev/null 2>&1; then
                    size_bytes=$(stat -c%s "$file") # GNU/Linux
                else
                    size_bytes=$(stat -f%z "$file") # BSD/macOS
                fi
            fi

            # Portable size formatting using awk (since macOS lacks numfmt)
            local size_human=$(awk -v size="${size_bytes:-0}" 'BEGIN {
                split("B KB MB GB TB", unit);
                i=1; while (size>=1024 && i<5) {size/=1024; i++}
                printf "%.1f%s", size, unit[i]
            }')

            # Cache for later (only matters if 1 file is passed)
            single_human_size="$size_human"
            single_is_gz="$is_gz"

            if [ "${size_bytes:-0}" -gt "${max_size_bytes:-0}" ]; then
                max_size_bytes="$size_bytes"
            fi

            if [ "${size_bytes:-0}" -gt "$hard_limit_bytes" ]; then
                any_large=true
                local label=$([ "$is_gz" = true ] && echo "uncompressed " || echo "")
                file_report+="\e[31m-> $file ($size_human ${label})[OVER ${hard_limit_mb}MB]\e[0m\n"
            elif [ "${size_bytes:-0}" -gt "$normal_limit_bytes" ]; then
                any_medium=true
                local label=$([ "$is_gz" = true ] && echo "uncompressed " || echo "")
                file_report+="\e[33m-> $file ($size_human ${label})[OVER ${normal_limit_mb}MB]\e[0m\n"
            else
                file_report+="   $file ($size_human)\n"
            fi
        fi
    done

    # 3. Any file over the hard limit: bail out to less/zless (multi-file too large to reason about)
    if [ "$any_large" = true ]; then
        if [ "$#" -gt 1 ]; then
            echo -e "\e[31mMulti-file open aborted. One or more files exceed ${hard_limit_mb}MB:\e[0m\n"
            echo -e "$file_report"
            return 1
        fi

        echo -e "\e[31mFile is too large for Neovim ($single_human_size).\e[0m"
        if [ "$single_is_gz" = true ]; then
            echo "Opening with 'zless' in 1 seconds..."
            sleep 1
            zless "$1"
        else
            echo "Opening with 'less' in 1 seconds..."
            sleep 1
            less "$1"
        fi
        return
    fi

    # 4. Medium files (200mb-1.5gb): check available RAM before using the stripped-down nvim
    if [ "$any_medium" = true ]; then
        if command -v free >/dev/null 2>&1; then
            # nvim needs roughly 2x a file's size in RAM to load it comfortably
            local needed_bytes=$((max_size_bytes * 2))
            local avail_bytes
            avail_bytes=$(free -b | awk '/^Mem:/ {print $7}')

            if [ -n "$avail_bytes" ] && [ "$avail_bytes" -lt "$needed_bytes" ]; then
                echo -e "\e[31mNot enough free RAM to safely open this in Neovim:\e[0m"
                free -h
                echo -e "$file_report"

                if [ "$#" -eq 1 ]; then
                    if [ "$single_is_gz" = true ]; then
                        echo "Opening with 'zless' in 1 seconds..."
                        sleep 1
                        zless "$1"
                    else
                        echo "Opening with 'less' in 1 seconds..."
                        sleep 1
                        less "$1"
                    fi
                else
                    echo "Open these individually with 'less' instead."
                fi
                return
            fi
        fi

        echo -e "\e[33mLarge file(s) detected, opening with a stripped-down Neovim:\e[0m"
        echo -e "$file_report"
        command nvim --clean -n -c "syntax off | set nonumber nonrelativenumber | filetype off" "$@"
        return
    fi

    # 5. Safe to proceed
    command nvim "$@"
}


# better fzf alias
fzf() {
    command fzf --height=40% --layout=reverse --border --margin=2% --bind "ctrl-j:down,ctrl-k:up" "$@"
}

# --- Helper function ---
d() {
    if [[ -z "$1" ]]; then
        cd ~/
        ls -lrth
        return 0
    fi
    cd "$1" || return 1
    ls -lrth
}

# --- make a directory and go to it ---
md() {
    if [[ -n "$2" ]]; then
        echo "all arguments after the first argument are being ignored"
    fi
    if [[ -n "$1" ]]; then
        mkdir -p $1
        cd $1
        ls -lrt
        return 0
    else
        echo "no arguments supplied. doing nothing"
        return 1
    fi
}

# --- Directory history navigation ---
b() {
    if (( _DIR_HISTORY_INDEX > 0 )); then
        local target="${_DIR_HISTORY[$((_DIR_HISTORY_INDEX - 1))]}"
        if cd "$target" 2>/dev/null && ls -lrt; then
            ((_DIR_HISTORY_INDEX--))
        else
            echo "Failed to go back."
        fi
    else
        echo "No previous directory stored."
    fi
}

f() {
    if (( _DIR_HISTORY_INDEX < ${#_DIR_HISTORY[@]} - 1 )); then
        local target="${_DIR_HISTORY[$((_DIR_HISTORY_INDEX + 1))]}"
        if cd "$target" 2>/dev/null && ls -lrt; then
            ((_DIR_HISTORY_INDEX++))
        else
            echo "Failed to go forward."
        fi
    else
        echo "No next directory stored."
    fi
}

# --- Open all files that match a grep input in split view ---
nvg() {
    local files=()
    for arg in "$@"; do
        files+=( *$arg* )
    done
    nv -O "${files[@]}"
}

# --- Open all files which you select from a fzf window ---
nvf() {
    local files
    files=$(fzf --multi) || return
    nv -O $(echo "$files")
}
