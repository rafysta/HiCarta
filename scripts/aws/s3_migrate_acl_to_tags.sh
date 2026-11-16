#!/usr/bin/env bash
# One-time migration: ACL-based public access -> "access" tags.
#
# For every object under the prefix, look at its CURRENT ACL:
#   AllUsers READ present  -> access=public   (stays public after the switch)
#   otherwise              -> access=noma     (stays private; the Noma lab can now read it)
# Objects that already carry an "access" tag are left alone.
#
#   s3_migrate_acl_to_tags.sh s3://uo-cgf/            # dry run: writes the plan only
#   APPLY=1 s3_migrate_acl_to_tags.sh s3://uo-cgf/    # actually tag
#
# Output: migrate_<bucket>_<timestamp>.tsv  (key, acl_public, current_tag, new_tag, result)
# Run the dry run first and look at the counts before APPLY=1.
set -euo pipefail
[ $# -eq 1 ] && [[ "$1" =~ ^s3://([^/]+)/?(.*)$ ]] || { sed -n '2,14p' "$0"; exit 1; }
bucket=${BASH_REMATCH[1]}; prefix=${BASH_REMATCH[2]}
PARALLEL=${PARALLEL:-8}
out="migrate_${bucket}_$(date +%Y%m%d_%H%M%S).tsv"

keys=$(aws s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" \
         --query 'Contents[].Key' --output text | tr '\t' '\n' | sed '/^None$/d;/^$/d')
n=$(printf '%s\n' "$keys" | sed '/^$/d' | wc -l)
echo "$n object(s) under s3://$bucket/$prefix   (APPLY=${APPLY:-0})"

export bucket APPLY
printf '%s\n' "$keys" | xargs -P "$PARALLEL" -d '\n' -I{} sh -c '
  key=$1
  pub=$(aws s3api get-object-acl --bucket "$bucket" --key "$key" \
          --query "Grants[?Grantee.URI==\`http://acs.amazonaws.com/groups/global/AllUsers\` && (Permission==\`READ\` || Permission==\`FULL_CONTROL\`)] | length(@)" \
          --output text 2>/dev/null || echo ERR)
  cur=$(aws s3api get-object-tagging --bucket "$bucket" --key "$key" \
          --query "TagSet[?Key==\`access\`].Value | [0]" --output text 2>/dev/null || echo ERR)
  [ "$cur" = None ] && cur="-"
  if [ "$pub" = ERR ] || [ "$cur" = ERR ]; then new="?"; res="read-error"
  elif [ "$cur" != "-" ]; then new="$cur"; res="kept"
  else
    if [ "$pub" -gt 0 ]; then new=public; else new=noma; fi
    if [ "${APPLY:-0}" = 1 ]; then
      aws s3api put-object-tagging --bucket "$bucket" --key "$key" \
        --tagging "{\"TagSet\":[{\"Key\":\"access\",\"Value\":\"$new\"}]}" >/dev/null \
        && res="tagged" || res="TAG-FAILED"
    else res="planned"; fi
  fi
  printf "%s\t%s\t%s\t%s\t%s\n" "$key" "$([ "$pub" = ERR ] && echo ? || { [ "$pub" -gt 0 ] && echo yes || echo no; })" "$cur" "$new" "$res"
' _ {} | sort > "$out"

echo "plan/result -> $out"
echo "--- new_tag x result ---"
cut -f4,5 "$out" | sort | uniq -c
