#!/usr/bin/env bash
# ============================================================================
# convert_hic200_to_hic.sh
#   hic200-cpp output (.txt.gz: bin1 <tab> bin2 <tab> score) -> Juicer .hic
#
# The .hic is compressed + indexed + multi-resolution, so it is far smaller than
# an SQLite copy and plugs straight into HiCarta's fast .hic path.
#
# Requires: Java, and juicer_tools.jar (https://github.com/aidenlab/juicer/wiki).
#
# Usage:
#   JUICER=/path/to/juicer_tools.jar \
#     bash convert_hic200_to_hic.sh bin_def_200bp.txt file1.txt.gz [file2.txt.gz ...]
#
#   Produces file1.hic next to each input. Set RES to change resolutions.
# ============================================================================
set -euo pipefail

JUICER="${JUICER:-juicer_tools.jar}"
RES="${RES:-200,1000,2000,5000,10000,20000,50000,100000}"
JMEM="${JMEM:-6g}"

if [ "$#" -lt 2 ]; then
  echo "Usage: JUICER=juicer_tools.jar bash $0 <bin_def.txt> <file.txt.gz> [more.txt.gz ...]" >&2
  exit 1
fi
BINDEF="$1"; shift

# chrom.sizes from the bin definition (length = max end + 1 per chr, in order)
CHROMSIZE="$(mktemp)"
awk -F'\t' 'NR>1{ if(!($2 in seen)){seen[$2]=1; ord[++n]=$2}
                  if($4+1>len[$2]) len[$2]=$4+1 }
            END{ for(i=1;i<=n;i++) print ord[i]"\t"len[ord[i]] }' "$BINDEF" > "$CHROMSIZE"
echo "chrom.sizes:"; cat "$CHROMSIZE"

for GZ in "$@"; do
  OUT="${GZ%.txt.gz}.hic"
  echo "Converting $GZ -> $OUT"
  SHORT="$(mktemp)"
  # bin index -> chr + midpoint; emit Juicer "short with score", sorted by chr/pos
  zcat "$GZ" | awk -F'\t' -v BD="$BINDEF" '
    BEGIN{ while((getline line < BD)>0){ n=split(line,a,"\t");
             if(a[1]=="bin") continue; chr[a[1]]=a[2]; mid[a[1]]=a[3]+100 } }
    NR>1 && ($1 in chr) && ($2 in chr){
      print "0",chr[$1],mid[$1],"0","1",chr[$2],mid[$2],"1",$3 }
  ' OFS='\t' | sort -k2,2 -k6,6 -k3,3n -k7,7n > "$SHORT"
  java -Xmx"$JMEM" -jar "$JUICER" pre -n -r "$RES" "$SHORT" "$OUT" "$CHROMSIZE"
  rm -f "$SHORT"
  echo "  wrote $OUT"
done
rm -f "$CHROMSIZE"
echo "Done."
