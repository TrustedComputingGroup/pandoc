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
DOCKER_MD=$DOCKER_WD/spec.md

OUT="${DOCKER_WD}/output.pdf"

SCRIPT_OPTS="--pdf=output.pdf spec.md"
DOCKER_OPTS="-v $WD:$DOCKER_WD"
DOCKER_COMMAND="cp $DOCKER_MD .; /usr/bin/build.sh $SCRIPT_OPTS; cp ./output.* $DOCKER_WD"
IMAGE_NAME="ghcr.io/trustedcomputinggroup/pandoc"

eval "docker run $DOCKER_OPTS --entrypoint /bin/sh $IMAGE_NAME -c '$DOCKER_COMMAND'"

if [ $? -eq 0 ]; then
  echo "Generated spec at $OUT"
else
  echo "Failed to generate spec"
fi
