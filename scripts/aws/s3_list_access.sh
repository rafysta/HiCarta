#!/usr/bin/env bash
# Show the "access" tag of every object under a prefix (untagged = "-", i.e.
# readable by nobody but the bucket admins).
#   s3_list_access.sh s3://uo-cgf/P/020/
set -euo pipefail
[ $# -eq 1 ] && [[ "$1" =~ ^s3://([^/]+)/(.*)$ ]] || { echo "usage: $0 s3://bucket/prefix" >&2; exit 1; }
bucket=${BASH_REMATCH[1]}; prefix=${BASH_REMATCH[2]}
aws s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" \
    --query 'Contents[].Key' --output text | tr '\t' '\n' | sed '/^None$/d;/^$/d' |
while read -r key; do
  tag=$(aws s3api get-object-tagging --bucket "$bucket" --key "$key" \
          --query "TagSet[?Key=='access'].Value | [0]" --output text 2>/dev/null || echo "-")
  [ "$tag" = None ] && tag="-"
  printf '%-8s %s\n' "$tag" "$key"
done
