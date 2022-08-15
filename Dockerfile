FROM pandoc/latex:2.19

COPY ./img/* /resources/img/
COPY ./template/* /resources/templates/

RUN tlmgr list
RUN tlmgr update --self && \
    tlmgr install \
    merriweather \
    fontaxes \
    mweights \
    mdframed \
    needspace \
    sourcesanspro \
    sourcecodepro \
    titling \
    ly1 \
    pagecolor \
    adjustbox \
    collectbox \
    titlesec \
    fvextra \
    pdftexcmds \
    footnotebackref \
    zref \
    fontawesome5 \
    footmisc \
    sectsty \
    koma-script \
    lineno \
    awesomebox \
    background \
    everypage \
    xurl \
    textpos \
    anyfontsize \
    transparent

RUN apk upgrade && apk add --no-cache \
    bash \
    coreutils \
    git \
    nodejs \
    npm \
    chromium

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

RUN npm install --global --unsafe-perm mermaid.cli@0.5.1 puppeteer@16.1.0 imgur@2.2.0 mermaid-filter@1.4.6

