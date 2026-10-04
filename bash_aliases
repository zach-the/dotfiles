# --- Aliases ---
alias sudo='sudo '
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias dush='du -sh --apparent-size'
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
pp() {
    local input path b64
    input=$(echo "$*" | xargs)
    path=$(realpath "$input") || return 1
    printf '%s' "$path"

    if command -v pbcopy &>/dev/null; then
        printf '%s' "$path" | pbcopy
    elif [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy &>/dev/null; then
        printf '%s' "$path" | wl-copy
    elif [ -n "$DISPLAY" ] && command -v xclip &>/dev/null; then
        printf '%s' "$path" | xclip -selection clipboard
    elif [ -n "$DISPLAY" ] && command -v xsel &>/dev/null; then
        printf '%s' "$path" | xsel --clipboard --input
    else
        # Headless / SSH: no clipboard helper and no display, so ask the
        # terminal emulator itself to set its clipboard via OSC 52.
        if [ -n "$TMUX" ] && printf '%s' "$path" | tmux load-buffer -w - 2>/dev/null; then
            : # tmux 3.2+ set its own buffer and forwarded OSC 52 to the terminal
        else
            b64=$(printf '%s' "$path" | base64 | tr -d '\n')
            printf '\033]52;c;%s\a' "$b64" > /dev/tty
        fi
    fi
    echo
}
alias rs='rsync -aHAX --info=progress2'
alias print_block='pyfiglet -f blocky -w $(tput cols)'

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
    command fzf --height=40% --layout=reverse --border --margin=2% --cycle --bind "ctrl-j:down,ctrl-k:up" "$@"
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

# --- Show a big pyfiglet banner, centered in the window, held until 'q' is pressed ---
# Positional args are joined into one message and auto word-wrapped (with a blank
# line inserted at each wrap point) to fit the terminal; multiple args can also be
# used to force a paragraph break, e.g. banner "FIGURE OUT" "HYPERSCALE".
_banner_render_width() {
    local out row maxw=0
    out=$(pyfiglet -f blocky -j left -w 4096 "${1// /   }" | sed 's/[[:space:]]*$//')
    while IFS= read -r row; do
        (( ${#row} > maxw )) && maxw=${#row}
    done <<< "$out"
    echo "$maxw"
}

_banner_wrap() {
    local text="$1" cols="$2"
    local -a words=($text)
    local current="" candidate w word
    for word in "${words[@]}"; do
        candidate="${current:+$current }$word"
        w=$(_banner_render_width "$candidate")
        if [[ -z "$current" || "$w" -le "$cols" ]]; then
            current="$candidate"
        else
            printf '%s\n' "$current"
            current="$word"
        fi
    done
    [[ -n "$current" ]] && printf '%s\n' "$current"
}

banner() {
    local justify="c"
    local paragraphs=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --alignment)
                case "$2" in
                    l|c|r) justify="$2" ;;
                    *) echo "banner: --alignment must be l, c, or r" >&2; return 1 ;;
                esac
                shift 2
                ;;
            *)
                paragraphs+=("$1")
                shift
                ;;
        esac
    done
    if [[ ${#paragraphs[@]} -eq 0 ]]; then
        echo "banner: no message given" >&2
        return 1
    fi

    local cols rows
    cols=$(tput cols)
    rows=$(tput lines)

    # Word-wrap each paragraph to fit the terminal width. Wrapped lines that
    # came from the same paragraph stay tight together (one blank line
    # between them); separate paragraph arguments become distinct groups
    # whose vertical spacing gets computed further down.
    local -a lines=() group_counts=()
    local para wrapped count
    for para in "${paragraphs[@]}"; do
        count=0
        while IFS= read -r wrapped; do
            lines+=("$wrapped")
            (( count++ ))
        done < <(_banner_wrap "$para" "$cols")
        group_counts+=("$count")
    done

    # Render each line, trimming trailing whitespace pyfiglet pads each row out to.
    local -a blocks=() widths=() heights=()
    local line block row maxw w h
    for line in "${lines[@]}"; do
        block=$(pyfiglet -f blocky -j left -w "$cols" "${line// /   }" | sed 's/[[:space:]]*$//')
        blocks+=("$block")
        maxw=0
        h=0
        while IFS= read -r row; do
            w=${#row}
            (( w > maxw )) && maxw=$w
            (( h++ ))
        done <<< "$block"
        widths+=("$maxw")
        heights+=("$h")
    done

    # Group width: the bounding box used to justify every line consistently.
    local group_width=0
    for w in "${widths[@]}"; do (( w > group_width )) && group_width=$w; done
    local left_pad=$(( (cols - group_width) / 2 ))
    (( left_pad < 0 )) && left_pad=0

    # Each paragraph's group height: its wrapped lines plus a blank line
    # between each of them.
    local -a group_heights=()
    local gc idx=0 gh j
    for gc in "${group_counts[@]}"; do
        gh=0
        for (( j=0; j<gc; j++ )); do
            (( gh += heights[idx] ))
            (( j < gc - 1 )) && (( gh++ ))
            (( idx++ ))
        done
        group_heights+=("$gh")
    done

    local ngroups=${#group_heights[@]}
    local total_content_height=0
    for h in "${group_heights[@]}"; do (( total_content_height += h )); done

    # For a single paragraph, keep the classic centered-block behavior. For
    # multiple separate string arguments, spread the leftover vertical space
    # evenly before, between, and after each one (space-evenly layout).
    local -a gaps=()
    if (( ngroups > 1 )); then
        local remaining=$(( rows - total_content_height ))
        (( remaining < 0 )) && remaining=0
        local nslots=$(( ngroups + 1 ))
        local base=$(( remaining / nslots ))
        local extra=$(( remaining % nslots ))
        local s
        for (( s=0; s<nslots; s++ )); do
            gaps+=("$(( base + (s < extra ? 1 : 0) ))")
        done
    else
        local top_pad=$(( (rows - total_content_height) / 2 ))
        (( top_pad < 0 )) && top_pad=0
        gaps+=("$top_pad")
        gaps+=("$top_pad")
    fi

    # Draw on the terminal's alternate screen (like vim/less) so the original
    # screen and scrollback come back untouched on exit. Ctrl-C also restores it.
    local old_int_trap
    old_int_trap=$(trap -p INT)
    tput smcup
    tput clear
    trap 'tput rmcup; trap - INT; '"$old_int_trap"'; return 130' INT
    local i pad
    for (( i=0; i<gaps[0]; i++ )); do echo; done

    idx=0
    local gi gcount
    for (( gi=0; gi<ngroups; gi++ )); do
        gcount=${group_counts[$gi]}
        for (( j=0; j<gcount; j++ )); do
            block="${blocks[$idx]}"
            w="${widths[$idx]}"
            case "$justify" in
                c) pad=$(( (cols - w) / 2 )) ;;
                l) pad=$left_pad ;;
                r) pad=$(( left_pad + group_width - w )) ;;
            esac
            (( pad < 0 )) && pad=0
            while IFS= read -r row; do
                printf '%*s%s\n' "$pad" "" "$row"
            done <<< "$block"
            (( j < gcount - 1 )) && echo
            (( idx++ ))
        done
        (( gi < ngroups - 1 )) && for (( i=0; i<gaps[gi+1]; i++ )); do echo; done
    done
    (( ngroups > 1 )) && for (( i=0; i<gaps[ngroups]; i++ )); do echo; done

    local key
    while true; do
        read -n 1 -s -r key
        [[ "$key" == "q" ]] && break
    done
    tput rmcup
    trap - INT
    eval "$old_int_trap"
}
alias banner='banner --alignment l'
# --- Plex Media Server control ---
alias plex-kill='sudo systemctl stop plexmediaserver'
alias plex-start='sudo systemctl start plexmediaserver'
alias plex-restart='sudo systemctl restart plexmediaserver'

# --- Jellyfin Media Server control ---
alias jellyfin-start='sudo systemctl start jellyfin'
alias jellyfin-stop='sudo systemctl stop jellyfin'
alias jellyfin-restart='sudo systemctl restart jellyfin'

# --- Copy photos/videos off a camera card and rename them by creation date ---
# Renamed to yyyy-mm-dd-hhmm.ext (24h time), e.g. Jan 3 2026 3:38pm -> 2026-01-03-1538.png
copy_from_camera_card() {
    local usage="Usage: copy_from_camera_card [--change_date N|yyyy_mm_dd] <source> <destination>

Copies files from <source> to <destination> with rsync (progress bar shown),
then renames every file under <destination> to:

    yyyy-mm-dd-hhmm.ext   (24-hour time, read from each file's own creation metadata)

  e.g. a photo shot January 3, 2026 at 3:38pm -> 2026-01-03-1538.png

If two files land on the same minute, '-2', '-3', etc. are appended before
the extension so nothing gets overwritten. Safe to re-run on the same
destination (already-renamed files are left alone).

Options:
  --change_date N           Replace the DATE portion with 'N days ago'
                             (0 = today, 1 = yesterday, 2 = two days ago, ...).
                             The TIME portion still comes from each file's
                             metadata. Useful when the camera's clock had the
                             wrong date set but the time-of-day is still correct.
  --change_date yyyy_mm_dd   Replace the DATE portion with this exact date
                             instead, e.g. --change_date 2026_01_03.
  -h, --help                 Show this help message.

Requires: rsync, exiftool (perl-image-exiftool), jq."

    local change_date="" override_date="" src="" dest=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                echo "$usage"
                return 0
                ;;
            --change_date)
                if [[ -z "$2" ]]; then
                    echo "copy_from_camera_card: --change_date requires a value" >&2
                    return 1
                fi
                change_date="$2"
                shift 2
                ;;
            --change_date=*)
                change_date="${1#*=}"
                shift
                ;;
            -*)
                echo "copy_from_camera_card: unknown option '$1'" >&2
                echo "$usage"
                return 1
                ;;
            *)
                if [[ -z "$src" ]]; then
                    src="$1"
                elif [[ -z "$dest" ]]; then
                    dest="$1"
                else
                    echo "copy_from_camera_card: unexpected argument '$1'" >&2
                    echo "$usage"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$src" || -z "$dest" ]]; then
        echo "$usage"
        return 1
    fi

    local tool
    for tool in rsync exiftool jq; do
        if ! command -v "$tool" &>/dev/null; then
            echo "copy_from_camera_card: '$tool' is required but not installed" >&2
            return 1
        fi
    done

    if [[ -n "$change_date" ]]; then
        if [[ "$change_date" =~ ^[0-9]+$ ]]; then
            override_date=$(date -d "${change_date} days ago" +%Y-%m-%d) || return 1
        elif [[ "$change_date" =~ ^[0-9]{4}_[0-9]{2}_[0-9]{2}$ ]]; then
            override_date=$(date -d "${change_date//_/-}" +%Y-%m-%d 2>/dev/null) || {
                echo "copy_from_camera_card: invalid date '$change_date'" >&2
                return 1
            }
        else
            echo "copy_from_camera_card: --change_date must be a number of days ago (0, 1, 2, ...) or an exact yyyy_mm_dd date" >&2
            return 1
        fi
    fi

    mkdir -p "$dest" || return 1

    local src_arg="$src" dest_arg="$dest"
    [[ -d "$src_arg" && "$src_arg" != */ ]] && src_arg+="/"
    [[ "$dest_arg" != */ ]] && dest_arg+="/"

    echo "Copying from '$src' to '$dest'..."
    rsync -aHAX --info=progress2 "$src_arg" "$dest_arg" || return 1

    echo "Renaming files by creation date..."
    local file fname ext stamp date_part time_part tag dir candidate n
    local skipped=0 renamed=0 duplicates=0
    while IFS= read -r -d '' file; do
        stamp=$(exiftool -j -DateTimeOriginal -CreateDate -MediaCreateDate -TrackCreateDate -FileModifyDate "$file" 2>/dev/null \
            | jq -r '.[0] | .DateTimeOriginal // .CreateDate // .MediaCreateDate // .TrackCreateDate // .FileModifyDate // empty')

        if [[ -z "$stamp" ]]; then
            echo "  skip (no date metadata): $file" >&2
            ((skipped++))
            continue
        fi

        date_part=$(awk '{print $1}' <<< "$stamp" | tr ':' '-')
        time_part=$(awk '{print $2}' <<< "$stamp" | cut -c1-5 | tr -d ':')
        [[ -n "$override_date" ]] && date_part="$override_date"
        tag="${date_part}-${time_part}"

        dir="${file%/*}"
        fname="${file##*/}"
        [[ "$fname" == *.* ]] && ext="${fname##*.}" || ext=""
        candidate="$dir/$tag${ext:+.$ext}"

        # Walk collisions: a byte-identical file already at the candidate name
        # means this is the same shot re-copied (e.g. a re-run against the same
        # source), so drop the redundant copy instead of renaming it with a
        # suffix. Only genuinely different files taken in the same minute get
        # a -2, -3, ... suffix.
        n=1
        while [[ -e "$candidate" && "$candidate" != "$file" ]]; do
            if cmp -s -- "$file" "$candidate"; then
                rm -f -- "$file"
                ((duplicates++))
                continue 2
            fi
            ((n++))
            candidate="$dir/${tag}-${n}${ext:+.$ext}"
        done

        if [[ "$candidate" != "$file" ]]; then
            mv -n -- "$file" "$candidate"
            ((renamed++))
        fi
    done < <(find "$dest" -type f -print0)

    echo "Done. Renamed $renamed file(s), dropped $duplicates duplicate(s), skipped $skipped file(s) with no date metadata."
}
