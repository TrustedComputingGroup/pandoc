#!/usr/bin/env bash

set -e

docker build . --tag=test -f Dockerfile

DOCKER_IMAGE="test" ./docker_run --puppeteer --gitversion --latex=sample1.tex --pdf=sample1.pdf --docx=sample1.docx sample1.md
