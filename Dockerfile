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
    tocloft \
    tools

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

# Install Source Sans Pro, Source Serif Pro, and Source Code Pro
RUN wget https://github.com/adobe-fonts/source-code-pro/archive/2.030R-ro/1.050R-it.zip && \
    unzip 1.050R-it.zip && \
    cp source-code-pro-2.030R-ro-1.050R-it/TTF/*.ttf /usr/share/fonts/TTF/ && \
    wget https://github.com/adobe-fonts/source-serif-pro/archive/2.000R.zip && \
    unzip 2.000R.zip && \
    cp source-serif-2.000R/TTF/*.ttf /usr/share/fonts/TTF/ && \
    wget https://github.com/adobe-fonts/source-sans-pro/archive/2.020R-ro/1.075R-it.zip && \
    unzip 1.075R-it.zip && \
    cp source-sans-2.020R-ro-1.075R-it/TTF/*.ttf /usr/share/fonts/TTF/ && \
    fc-cache -f -v

RUN pip install pandocfilters

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

RUN npm install --global --unsafe-perm mermaid.cli@0.5.1 puppeteer@19.8.5 imgur@2.2.0 mermaid-filter@1.4.6 typescript@5.0.4

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

COPY build.sh /usr/bin/build.sh
ENTRYPOINT ["/usr/bin/build.sh"]
CMD ["--help"]
