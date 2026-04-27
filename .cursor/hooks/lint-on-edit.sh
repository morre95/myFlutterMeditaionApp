#!/bin/bash
# Hook: Run lightweight formatting after file edits
# Registered in .cursor/hooks.json under afterFileEdit
#
# Cursor passes event data as JSON on stdin. The JSON contains a "path" field
# with the absolute path of the file that was edited.

input=$(cat)
FILE_PATH=$(echo "$input" | jq -r '.path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

EXTENSION="${FILE_PATH##*.}"

case "$EXTENSION" in
  dart)
    if command -v dart >/dev/null 2>&1; then
      dart format "$FILE_PATH" >/dev/null 2>&1
    fi
    ;;
  *)
    # No formatter configured for this file type
    ;;
esac
