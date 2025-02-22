#!/usr/bin/env bash

set -e  # Exit on error

SELECTED="/tmp/fzf_selected"
SIZE="/tmp/fzf_total"

# Clear previous selections
> "$SELECTED"
> "$SIZE"

SELECTED_ITEMS=$(find ~ -mindepth 1 -maxdepth 5 | fzf --multi --preview 'du -sh {}' \
    --bind "space:execute-silent(
        grep -Fxq {} $SELECTED && sed -i '\|^{}$|d' $SELECTED || echo {} >> $SELECTED;
        du -ch \$(cat $SELECTED 2>/dev/null) | grep total$ > $SIZE
    )+toggle" \
    --bind "ctrl-r:execute-silent(truncate -s 0 $SELECTED; truncate -s 0 $SIZE)+reload(find ~ -mindepth 1 -maxdepth 5)" \
    --preview 'cat /tmp/fzf_total || echo "Total size: 0B"' \
    --bind "ctrl-a:execute-silent(find ~ -mindepth 1 -maxdepth 5 > $SELECTED; du -ch \$(cat $SELECTED) | grep total$ > $SIZE)+select-all"
)

# Exit if no selection is made
[[ -z "$SELECTED_ITEMS" ]] && echo "No files selected." && exit 1

# Display the final total size
TOTAL_SIZE=$(du -ch $(cat "$SELECTED" 2>/dev/null) | grep "total$" | awk '{print $1}')
echo "Total size of selected items: $TOTAL_SIZE"
echo "Files and directories selected:"
echo $SELECTED_ITEMS
