#!/usr/bin/env bash
set -eo pipefail

declare -A ICONS=(
  ["firefox-bin"]=""
  ["firefox"]=""
  ["dev.zed.Zed"]=""
  ["Alacritty"]=""
  ["kitty"]=""
  ["code"]=""
  ["chromium"]=""
  ["org.gnome.Nautilus"]=""
)

declare -A WS_APPS

# Собрать все рабочие столы с окнами
current_app=""
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*App\ ID:\ \"(.*)\" ]]; then
        current_app="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*Workspace\ ID:\ ([0-9]+) ]]; then
        ws="${BASH_REMATCH[1]}"
        icon="${ICONS[$current_app]:-}"
        if [[ -z "${WS_APPS[$ws]:-}" ]]; then
            WS_APPS[$ws]="$icon"
        else
            if [[ ! "${WS_APPS[$ws]}" =~ "$icon" ]]; then
                WS_APPS[$ws]+=" $icon"
            fi
        fi
    fi
done < <(niri msg windows 2>/dev/null || true)

# Собрать все видимые рабочие столы
visible_ws_ids=()
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*\*?[[:space:]]*([0-9]+) ]]; then
        visible_ws_ids+=("${BASH_REMATCH[1]}")
    fi
done < <(niri msg workspaces 2>/dev/null || true)

# Объединить все рабочие столы (с окнами и видимые)
all_ws_ids=()
for ws in "${!WS_APPS[@]}"; do
    all_ws_ids+=("$ws")
done
for ws in "${visible_ws_ids[@]}"; do
    if printf '%s\n' "${all_ws_ids[@]}" | grep -q -x "$ws"; then
        continue
    fi
    all_ws_ids+=("$ws")
done

# Отсортировать рабочие столы по их ID
IFS=$'\n' sorted_ws_ids=($(sort -n <<<"${all_ws_ids[*]}"))
unset IFS

# Построить вывод
out=""
for ws_id in "${sorted_ws_ids[@]}"; do
    apps="${WS_APPS[$ws_id]:--}"
    out+="[$ws_id] $apps  "
done

# Вывести результат в формате JSON
python3 -c "
import json
out = '''$out'''
print(json.dumps({'text': out.strip()}))
"
