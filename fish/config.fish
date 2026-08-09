if status is-interactive
    set -x GPG_TTY (tty)
end

set -g fish_greeting

fish_add_path $HOME/go/bin

# zoxide config
set -gx _ZO_EXCLUDE_DIRS "$HOME:$HOME/Downloads/*:$HOME/.cache/*:/tmp/*"
set -gx _ZO_MAXAGE 5000

zoxide init --cmd cd fish | source

function ls
    eza -lah \
        --icons=auto \
        --git \
        --group-directories-first \
        --header \
        --time-style="+%d.%m.%Y" \
        --classify=auto \
        $argv
end

function sync-update
    doas emerge --sync && doas emerge --ask \
        --verbose \
        --update \
        --newuse \
        @world
end

function update
    doas emerge --ask \
        --verbose \
        --update \
        --newuse \
        @world
end
