#!/usr/bin/env bash
# Set the "access" tag on every object under an S3 prefix (or on one object).
#
#   s3_set_access.sh s3://uo-cgf/P/020/wt_Db_MHM_mix1/  noma     # Noma lab only
#   s3_set_access.sh s3://uo-cgf/P/020/wt_Db_MHM_mix1/  p01      # share with P01
#   s3_set_access.sh s3://uo-cgf/P/020/wt_Db_MHM_mix1/  public   # publish
#   s3_set_access.sh s3://uo-cgf/P/020/x/x.hic          noma     # single object
#   DRY_RUN=1 s3_set_access.sh ...                               # list only
#
# Levels: <lab name> < p01 < public  (who can read is decided by the IAM policies in
# this folder, not by this script). Note: put-object-tagging REPLACES the
# whole tag set, so any other tag on the object is dropped. Re-uploading an
# object also resets its tags -- re-run this after every sync.
set -euo pipefail

usage() { sed -n '2,12p' "$0"; exit 1; }
[ $# -eq 2 ] || usage
target=$1; level=$2
# Lab tags in use. Add a lab here AND create its IAM policy (copy
# policy-noma-reader.json, change "noma") -- a tag no policy mentions is
# readable by nobody.
LABS="noma"
case " $LABS p01 public " in *" $level "*) ;; *) echo "level must be one of: $LABS p01 public" >&2; exit 1;; esac
[[ "$target" =~ ^s3://([^/]+)/(.*)$ ]] || { echo "target must be s3://bucket/prefix" >&2; exit 1; }
bucket=${BASH_REMATCH[1]}; prefix=${BASH_REMATCH[2]}
PARALLEL=${PARALLEL:-8}

# One object or a whole prefix? A prefix ends with "/" (or matches nothing exact).
if [[ "$prefix" != */ ]] && aws s3api head-object --bucket "$bucket" --key "$prefix" >/dev/null 2>&1; then
  keys=$(printf '%s\n' "$prefix")
else
  keys=$(aws s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" \
           --query 'Contents[].Key' --output text | tr '\t' '\n' | sed '/^None$/d;/^$/d')
fi
n=$(printf '%s\n' "$keys" | sed '/^$/d' | wc -l)
[ "$n" -gt 0 ] || { echo "no objects under $target" >&2; exit 1; }
echo "$n object(s) under $target -> access=$level"

if [ "${DRY_RUN:-0}" = 1 ]; then printf '%s\n' "$keys"; exit 0; fi

export bucket level
printf '%s\n' "$keys" | xargs -P "$PARALLEL" -I{} sh -c '
  aws s3api put-object-tagging --bucket "$bucket" --key "$1" \
      --tagging "{\"TagSet\":[{\"Key\":\"access\",\"Value\":\"$level\"}]}" >/dev/null \
    && echo "  ok  $1" || echo "  FAIL $1" >&2' _ {}
