#!/usr/bin/env bash
# Download every gem listed in Gemfile.lock into a bundler cache dir,
# using plain curl (reliable on this network) instead of bundler's HTTP stack.
# Usage: download-gems.sh <Gemfile.lock> <cache-dir> [mirror-base]
set -uo pipefail

LOCK=${1:?Gemfile.lock path}
CACHE=${2:?cache dir}
BASE=${3:-https://mirrors.tuna.tsinghua.edu.cn/rubygems/gems}

mkdir -p "$CACHE"

# Extract "name (version)" pairs from the GEM specs section.
awk '/^GEM$/{s=1} /^PLATFORMS$/{s=0} s && /^    [a-zA-Z0-9_.-]+ \(/{
  line=$0
  sub(/^    /,"",line)
  name=line; sub(/ \(.*/,"",name)
  ver=line; sub(/^[^(]*\(/,"",ver); sub(/\).*$/,"",ver)
  print name "-" ver ".gem"
}' "$LOCK" | sort -u > "$CACHE/_gemlist.txt"

total=$(wc -l < "$CACHE/_gemlist.txt" | tr -d ' ')
have=0; miss=0
: > "$CACHE/_missing.txt"
while IFS= read -r f; do
  if [ ! -s "$CACHE/$f" ]; then
    if curl -fsSL --retry 3 --retry-delay 2 --max-time 180 -o "$CACHE/$f.part" "$BASE/$f"; then
      mv "$CACHE/$f.part" "$CACHE/$f"
    else
      rm -f "$CACHE/$f.part"
      echo "$f" >> "$CACHE/_missing.txt"
    fi
  fi
  have=$((have+1))
  [ $((have % 25)) -eq 0 ] && echo "progress: $have/$total"
done < "$CACHE/_gemlist.txt"

miss=$(wc -l < "$CACHE/_missing.txt" | tr -d ' ')
echo "DONE: $total gems, $miss missing"
[ "$miss" != "0" ] && head -20 "$CACHE/_missing.txt"
exit 0
