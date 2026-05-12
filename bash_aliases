# --- Aliases ---
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias zg='rg -z'
alias rgs='rg -S'
alias zgs='rg -z -S'
alias fzv='tmp=$(fzf) && echo $tmp && nvim $tmp'
alias fzd='tmp=$(fd --type d -d 4 | fzf) && echo $tmp && d $tmp'
alias e='clear && exit'
alias ll='ls -lrt'
alias l='ls -lrt'
alias la='ls -la'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history | tail -n1 | sed -e "s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//")"'
alias py='python3'
alias tl='tail -Fn 70'
alias cp='cp -a'
alias lg='ls -lrga | rg -i'
alias nvs='nv -O'
alias work='ssh -Y zb900042@lvnvda8240.lvn.broadcom.net'
alias redhawk_results='/project/priest/master_scripts/user_scripts/parse_redhawk_sc_block_rpts.ftc.py'
alias color_test='for i in {0..7}; do printf "\e[48;5;${i}m  "; done; printf "\e[0m\n"; for i in {8..15}; do printf "\e[48;5;${i}m  "; done; printf "\e[0m\n"'
alias zd='~/dotfiles/zd'
alias pp='realpath'
alias rs='rsync -aHAX --info=progress2'

# tmux session manager/attaching
tm() {
    local new_label="  [new session]"
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -vE '^.+-[0-9]{10}$')

    local choice
    if [[ -z "$sessions" ]]; then
        # No sessions exist — skip fzf and just create one
        tmux new-session
        return
    fi

    # Format numeric session names as "session #N" for display
    local display
    display=$(printf '%s\n' "$sessions" | sed 's/^[0-9][0-9]*$/session #&/')

    choice=$(printf "%s\n%s" "$display" "$new_label" | fzf --prompt="tmux> ")
    [[ -z "$choice" ]] && return

    if [[ "$choice" == "$new_label" ]]; then
        tmux new-session
    else
        # Reverse display label back to actual session name
        local session_name="$choice"
        [[ "$choice" =~ ^session\ #([0-9]+)$ ]] && session_name="${BASH_REMATCH[1]}"
        
        # Create a new grouped session with a unique name based on time
        # This allows multiple terminals to view different windows independently.
        # We also set destroy-unattached on the new session so it cleans up when detached.
        local group_session="${session_name}-$(date +%s)"
        tmux new-session -t "$session_name" -s "$group_session" \; set-option -t "$group_session" destroy-unattached on
    fi
}

# safe nvim (any file over 50mb will automatically use less/zless)
nv() {
    # 1. No arguments? Just open nvim.
    if [ "$#" -eq 0 ]; then
        command nvim
        return
    fi

    local limit_mb=50
    local limit_bytes=$((limit_mb * 1024 * 1024))
    local too_large=false
    local file_report=""
    
    # Variables to cache single-file data so we don't recalculate in Step 4
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

            # Cache for Step 4 (only matters if 1 file is passed)
            single_human_size="$size_human"
            single_is_gz="$is_gz"

            # Safety check: ensure size_bytes is a number before comparing
            if [ "${size_bytes:-0}" -gt "$limit_bytes" ]; then
                too_large=true
                local label=$([ "$is_gz" = true ] && echo "uncompressed " || echo "")
                file_report+="\e[31m-> $file ($size_human ${label})[OVER LIMIT]\e[0m\n"
            else
                file_report+="   $file ($size_human)\n"
            fi
        fi
    done

    # 3. Multi-file Logic: Abort if any file is > limit
    if [ "$#" -gt 1 ] && [ "$too_large" = true ]; then
        echo -e "\e[31mMulti-file open aborted. One or more files exceed ${limit_mb}MB:\e[0m\n"
        echo -e "$file_report"
        return 1
    fi

    # 4. Single-file Logic: Auto-switch to less/zless
    if [ "$#" -eq 1 ] && [ "$too_large" = true ]; then
        echo -e "\e[31mFile is too large for Neovim ($single_human_size).\e[0m"
        
        if [ "$single_is_gz" = true ]; then
            echo "Opening with 'zless' in 2 seconds..."
            sleep 2
            zless "$1"
        else
            echo "Opening with 'less' in 2 seconds..."
            sleep 2
            less "$1"
        fi
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
        ls -lrt
        return 0
    fi
    cd "$1" || return 1
    ls -lrt
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
