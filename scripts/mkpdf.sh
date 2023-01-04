#!/bin/bash

MD=$1

WD=/tmp/mdwd
DOCKER_WD=/mnt/mdwd
mkdir -p $WD

if [[ ! -f "$MD" ]]; then
  echo "Produces an output pdf from the input md file at $WD/tcgspec.pdf"
  echo "Usage: mkpdf.sh <input_file.md>"
  exit 1
fi

cp $MD $WD/spec.md
MD=$WD/spec.md
DOCKER_MD=$DOCKER_WD/spec.md

# \newpage is rendered as the string "\newpage" in GitHub markdown.
# Transform horizontal rules into \newpages.
# Exception: the YAML front matter of the document, so undo the instance on the first line.
sed -i 's/^---$/\\newpage/g;1s/\\newpage/---/g' $MD

# Transform sections before the table of contents into addsec, which does not number them.
# While we're doing this, transform the case to all-caps.
sed -i '0,/\\tableofcontents/s/^# \(.*\)/\\addsec\{\U\1\}/g' $MD

# Get data
DATE=$(grep "date:" $MD | head -n 1 | cut -d ' ' -f 2)
YEAR=$(date --date=$DATE +%Y)
DATE_ENGLISH=$(date --date=$DATE "+%B %-d, %Y")

OUT="${DOCKER_WD}/tcgspec.pdf"

# Make PDF
PANDOC_OPTS="--embed-resources \
  --standalone \
  --template=/resources/template/eisvogel.latex \
  --filter=mermaid-filter \
  --filter=pandoc-crossref \
  --resource-path=.:/resources \
  --data-dir=/resources \
  --top-level-division=section \
  --variable=block-headings \
  --variable=numbersections \
  --variable=table-use-row-colors \
  --metadata=date-english:\"${DATE_ENGLISH}\" \
  --metadata=year:"${YEAR}" \
  --metadata=titlepage:true \
  --metadata=titlepage-background:/resources/img/greentop.png \
  --metadata=logo:/resources/img/tcg.png \
  --metadata=titlepage-rule-height:0 \
  --metadata=colorlinks:true \
  --metadata=contact:admin@trustedcomputinggroup.org \
  --from=markdown+implicit_figures+table_captions \
  --to=pdf \
  --output=${OUT}"

DOCKER_OPTS="-v $WD:$DOCKER_WD"
IMAGE_NAME="ghcr.io/trustedcomputinggroup/pandoc"

# Quotes around DATE_ENGLISH get messed up during expansion. Instead,
# quotes are added menually above and eval is used to execute the command.
eval "docker run $DOCKER_OPTS $IMAGE_NAME $DOCKER_MD $PANDOC_OPTS"

echo "Generated spec at $OUT"
