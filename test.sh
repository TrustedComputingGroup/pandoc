#!/usr/bin/env bash

set -e

hash="$(docker build . -q -f Dockerfile)"

DOCKER_IMAGE="${hash}" ./docker_run --puppeteer --gitversion --latex=sample1.tex --pdf=sample1.pdf --docx=sample1.docx sample1.md
