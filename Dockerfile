FROM pandoc/latex:2.19

COPY ./img/* /resources/img/
COPY ./template/* /resources/templates/
COPY ./filter/* /resources/filters/

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
    transparent \
    ulem

RUN apk upgrade && apk add --no-cache \
    bash \
    coreutils \
    git \
    nodejs \
    npm \
    chromium \
    python3 \
    py3-pip \
    yarn

RUN pip install pandocfilters

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

RUN npm install --global --unsafe-perm mermaid.cli@0.5.1 puppeteer@16.1.0 imgur@2.2.0 mermaid-filter@1.4.6 typescript@4.7.4

# Install latest pandiff, which has not been released in a while
# This pre-release build has --reference-doc support for docx output
RUN mkdir /src
RUN cd /src && git clone https://github.com/davidar/pandiff.git
RUN cd /src/pandiff && git checkout d1d468b2c4d81c622ff431ef718b1bf0daaa03db
RUN cd /src/pandiff && npm install @types/node --save-dev
RUN npm install /src/pandiff
