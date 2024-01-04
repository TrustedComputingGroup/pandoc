FROM pandoc/latex:3.1.1

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
    ulem \
    hardwrap \
    catchfile \
    ragged2e \
    enumitem \
    mathtools \
    fontspec \
    unicode-math \
    titlesec \
    newunicodechar \
    tools \
    changepage \
    draftwatermark \
    appendix \
    multirow

RUN apk upgrade && apk add --no-cache \
    bash \
    coreutils \
    sed \
    git \
    nodejs \
    npm \
    chromium \
    python3 \
    py3-pip \
    yarn

# Install MS core fonts, including Arial
RUN apk --no-cache add msttcorefonts-installer fontconfig && \
    update-ms-fonts && \
    fc-cache -f

# Install the Arial Unicode MS font as well
RUN wget https://github.com/kaienfr/Font/raw/master/font/ARIALUNI.TTF -P /usr/share/fonts/TTF/ && \
    fc-cache -f

# Install Source Code Pro
RUN wget https://github.com/adobe-fonts/source-code-pro/archive/refs/tags/2.042R-u/1.062R-i/1.026R-vf.zip && \
    unzip 1.026R-vf.zip && \
    cp source-code-pro-2.042R-u-1.062R-i-1.026R-vf/TTF/*.ttf /usr/share/fonts/TTF/ && \
    fc-cache -f

RUN pip install pandocfilters

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

RUN npm install --global --unsafe-perm mermaid.cli@0.5.1 puppeteer@19.8.5 imgur@2.2.0 mermaid-filter@1.4.7 typescript@5.0.4

# Install latest pandiff, which has not been released in a while
# This pre-release build has --reference-doc support for docx output
RUN mkdir /src
RUN cd /src && git clone https://github.com/davidar/pandiff.git
RUN cd /src/pandiff && git checkout d1d468b2c4d81c622ff431ef718b1bf0daaa03db
RUN cd /src/pandiff && npm install @types/node --save-dev
RUN npm install --global /src/pandiff

COPY ./img/* /resources/img/
COPY ./template/* /resources/templates/
COPY ./filter/* /resources/filters/

# mktexpk gets executed and needs a home dir, build one
RUN mkdir -m 0777 /home/user
ENV HOME="/home/user"

COPY ./filter/pandoc-crossref.yaml /home/user/.pandoc-crossref/config.yaml

COPY build.sh /usr/bin/build.sh
ENTRYPOINT ["/usr/bin/build.sh"]
CMD ["--help"]
