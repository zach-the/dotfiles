# --- Aliases ---
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias lg='ls -lrt | rg'
alias zg='rg -z'
alias rgs='rg -S'
alias zgs='rg -z -S'
alias fzv='tmp=$(fzf) && echo $tmp && nvim $tmp'
alias fzd='tmp=$(fd --type d -d 4 | fzf) && echo $tmp && d $tmp'
alias e='clear && exit'
alias ll='ls -lrt'
alias la='ls -A'
alias l='ls -CF'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history | tail -n1 | sed -e "s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//")"'
alias py='python3'
alias tl='tail -Fn 70'
alias tm='tmux a'
alias cp='cp -a'
alias lg='ls -lrga | rg -i'
alias nvs='nv -O'
alias work='ssh -Y zb900042@lvnvda8240.lvn.broadcom.net'
alias redhawk_results='/project/priest/master_scripts/user_scripts/parse_redhawk_sc_block_rpts.ftc.py'

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

    # 2. Pre-check all provided files (handling .gz expansion)
    for file in "$@"; do
        if [ -f "$file" ]; then
            local size_bytes
            local is_gz=false
            
            if [[ "$file" == *.gz ]]; then
                # Get uncompressed size from gzip header
                size_bytes=$(gzip -l "$file" | tail -n 1 | awk '{print $2}')
                is_gz=true
            else
                size_bytes=$(stat -c%s "$file")
            fi
            
            local size_human=$(numfmt --to=iec-i --suffix=B "$size_bytes")
            
            if [ "$size_bytes" -gt "$limit_bytes" ]; then
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
        local file="$1"
        # Determine size again for the specific message
        local size_bytes
        if [[ "$file" == *.gz ]]; then
            size_bytes=$(gzip -l "$file" | tail -n 1 | awk '{print $2}')
        else
            size_bytes=$(stat -c%s "$file")
        fi
        local size_human=$(numfmt --to=iec-i --suffix=B "$size_bytes")
        
        echo -e "\e[31mFile is too large for Neovim ($size_human).\e[0m"
        
        if [[ "$file" == *.gz ]]; then
            echo "Opening with 'zless' in 2 seconds..."
            sleep 2
            less "$file"
        else
            echo "Opening with 'less' in 2 seconds..."
            sleep 2
            less "$file"
        fi
        return
    fi

    # 5. Safe to proceed
    command nvim "$@"
}

# Safer fzf alias (use function)
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

# --- to easily diff two directories ---
zd ()
{ 
    if [[ -z "$2" ]]; then
        echo "you need 2 arguments";
        return 0;
    fi;

    diff -r -y --suppress-common-lines -W $(tput cols) \
        --exclude="*def" --exclude="eco?.tcl" --exclude="*csv" \
        --exclude="*log" --exclude="*rpt" --exclude="*\.shadow*" --expand-tabs "$1" "$2" | \
        # This sed captures the last two space-separated strings (the paths) 
        # on lines starting with 'diff'
        sed -E 's/^diff .* ([^ ]+) ([^ ]+)$/FILE: \1 <-> \2/' | \
        rg -v "Common\ subdirectories" | \
        # The -- tells rg that "FILE:" is a pattern, not a flag
        rg --color=always -- "FILE:.*|Only in |$" 
}
# --- same as above, but this one allows you to diff with a .shadow/ directory ---
zd_with_shadow ()
{ 
    if [[ -z "$2" ]]; then
        echo "you need 2 arguments";
        return 0;
    fi;

    diff -r -y --suppress-common-lines -W $(tput cols) \
        --exclude="*def" --exclude="eco?.tcl" --exclude="*csv" \
        --exclude="*log" --exclude="*rpt" --expand-tabs "$1" "$2" | \
        # This sed captures the last two space-separated strings (the paths) 
        # on lines starting with 'diff'
        sed -E 's/^diff .* ([^ ]+) ([^ ]+)$/FILE: \1 <-> \2/' | \
        rg -v "Common\ subdirectories" | \
        # The -- tells rg that "FILE:" is a pattern, not a flag
        rg --color=always -- "FILE:.*|Only in .*|$" 
}

qcursor_ssh_start () {
    cd /project/priest_4/giant/giant-2025.7.2/user/zb900042/PN99.0.LIB1.fp17.23Oct2025.dft.251025/impl/broadcom_cloud_noncritical_zb900042/
    so ~/.junklog /tools/ictools/bin/qcursor --ssh-container ./
    echo "started qcursordb"
    cd .qcursordata
}
