FROM pandoc/latex:3.1.1

# Packages that are needed despite not being used explicitly by the template:
# catchfile, hardwrap, lineno, needspace, zref
RUN tlmgr update --self && tlmgr install \
    adjustbox \
    anyfontsize \
    appendix \
    catchfile \
    draftwatermark \
    enumitem \
    fontspec \
    footnotebackref \
    fvextra \
    hardwrap \
    koma-script \
    lineno \
    luacode \
    mathtools \
    mdframed \
    multirow \
    needspace \
    newunicodechar \
    pagecolor \
    ragged2e \
    tex-gyre \
    textpos \
    titling \
    transparent \
    unicode-math \
    zref

RUN apk upgrade && apk add --no-cache \
    bash \
    chromium \
    coreutils \
    git \
    nodejs \
    npm \
    py3-pip \
    python3 \
    sed \
    yarn

# Install MS core fonts, including Arial
RUN apk --no-cache add msttcorefonts-installer fontconfig && \
    update-ms-fonts && \
    fc-cache -f

# Install the Arial Unicode MS font as well
RUN wget https://github.com/kaienfr/Font/raw/master/font/ARIALUNI.TTF -P /usr/share/fonts/TTF/ && \
    fc-cache -f

# Install Noto Sans Mono
RUN apk --no-cache add font-noto && \
    fc-cache -f

RUN pip install pandocfilters

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

RUN npm install --global --unsafe-perm puppeteer@21.7.0 imgur@2.3.0 mermaid-filter@1.4.7 typescript@5.3.3 pandiff@0.6.0

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
