ARG BASE=debian:bookworm-20240110-slim
FROM ${BASE} as build-pandoc

WORKDIR /usr/src/pandoc

# Install pandoc and pandoc-crossref
RUN apt update && apt install -y \
    cabal-install \
    g++ \
    git \
    pkg-config \
    zlib1g \
    zlib1g-dev

ENV PANDOC_REF=3.1.11.1
RUN git clone --branch=${PANDOC_REF} --depth=1 --quiet \
  https://github.com/jgm/pandoc /usr/src/pandoc

# Replace the default project config from the Pandoc repo.
COPY ./pandoc/cabal.project /usr/src/pandoc/cabal.project

# Fetch the dependencies separately, to increase the number of cases
# where the Docker layer cache helps us.
RUN cabal update && \
    cabal build --dependencies-only \
    pandoc

# This layer takes a VERY long time to build.
RUN cabal build -j \
    --disable-tests \
    --disable-bench \
    --allow-newer 'lib:pandoc' \
    pandoc-cli pandoc-crossref

# Copy just the binaries we want into /pandocbins/
RUN mkdir -p /pandocbins && \
    find dist-newstyle \
    -name 'pandoc*' -type f -perm -u+x \
    -exec strip '{}' ';' \
    -exec cp '{}' /pandocbins/ ';'

FROM ${BASE} as build-texlive

# Pass the correct platform to texlive build.
ARG TARGETPLATFORM

RUN if [ "${TARGETPLATFORM}" = "linux/arm64" ]; \
    then echo "aarch64-linux" > /ARCH; \
    elif [ "${TARGETPLATFORM}" = "linux/amd64" ]; \
    then echo "x86_64-linux" > /ARCH; \
    else echo "Unsupported architecture '${TARGETPLATFORM}'"; exit 1; \
    fi

RUN export ARCH=$(cat /ARCH) && echo "Building for ${ARCH}"

# fun fact: if curl is not present, install-tl will fail even though it claims to fall back to wget.
# TODO: Remove as many packages as possible from here and add them to a later package upgrade step.
# Ideally, this Dockerfile will be organized such that very long-running tasks that are infrequently
# modified are all up at the top.
RUN apt update && apt install -y \
    bash \
    coreutils \
    curl \
    git \
    perl \
    sed \
    wget \
    yarn

ENV MIRROR=https://ctan.math.illinois.edu/systems/texlive/tlnet/

# install texlive ourselves instead of relying on the pandoc docker images,
# so that we can control the cross-platform support (e.g., arm64 linux)
# This layer takes several minutes to build.
RUN export ARCH=$(cat /ARCH) && \
    wget "$MIRROR/install-tl-unx.tar.gz" && \
    tar xzvf ./install-tl-unx.tar.gz && \
    ./install-tl-*/install-tl -v --repository "${MIRROR}" --force-platform "${ARCH}" -s basic --no-interaction

RUN mkdir -p /texlivebins && cp -r /usr/local/texlive/*/* /texlivebins

FROM ${BASE} as build-fonts

RUN apt update && apt install -y \
    wget \
    xfonts-utils

# Install Arial via ttf-mscorefonts
RUN wget http://ftp.us.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.8.1_all.deb
RUN apt install -y cabextract
RUN dpkg -i ttf-mscorefonts-installer_3.8.1_all.deb

# Install the Arial Unicode MS font as well
RUN wget https://github.com/kaienfr/Font/raw/master/font/ARIALUNI.TTF -P /usr/share/fonts/TTF/

# Install Noto Sans Mono
RUN apt install -y fonts-noto

# Build's done. Copy what we need into the actual container for running.
FROM ${BASE} as run

# These binaries are by far the most costly part of the build. Grab them first to minimize invalidation.
COPY --from=build-pandoc /pandocbins /usr/local/bin

# These binaries are the second most costly part of the build.
COPY --from=build-texlive /texlivebins /usr/local/texlive

# Copy only the fonts we're using from the template.
COPY --from=build-fonts \
    /usr/share/fonts/truetype/msttcorefonts/Arial* \
    /usr/share/fonts/TTF/ARIAL* \
    /usr/share/fonts/truetype/noto/NotoSansMono* \
    /usr/share/fonts/

RUN apt update && apt install -y fontconfig && \
    fc-cache -f

RUN apt install -y \
    bash \
    chromium \
    moreutils \
    nodejs \
    npm \
    sed

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

RUN npm install --global --unsafe-perm puppeteer@21.7.0 imgur@2.3.0 mermaid-filter@1.4.7 typescript@5.3.3 pandiff@0.6.0

# Lazy: Just put both possible texlive paths into the path. Only one will get populated.
ENV PATH="${PATH}:/usr/local/texlive/bin/aarch64-linux:/usr/local/texlive/bin/x86_64-linux"

# Packages that are needed despite not being used explicitly by the template:
# catchfile, fancyvrb, hardwrap, lineno, lualatex-math, luatexspace, needspace, ninecolors, pgf, zref
RUN tlmgr update --self && tlmgr install \
    accsupp \
    adjustbox \
    appendix \
    amsmath \
    anyfontsize \
    adjustbox \
    anyfontsize \
    appendix \
    bookmark \
    booktabs \
    caption \
    catchfile \
    draftwatermark \
    enumitem \
    etoolbox \
    fancyhdr \
    fancyvrb \
    float \
    fontspec \
    footnotebackref \
    footnotehyper \
    fvextra \
    geometry \
    hardwrap \
    hyperref \
    koma-script \
    lineno \
    luacode \
    lualatex-math \
    luatexbase \
    mathtools \
    mdframed \
    microtype \
    multirow \
    needspace \
    newunicodechar \
    ninecolors \
    pagecolor \
    pdflscape \
    pgf \
    polyglossia \
    ragged2e \
    selnolig \
    setspace \
    tabularray \
    tex-gyre \
    textpos \
    titling \
    transparent \
    unicode-math \
    upquote \
    varwidth \
    xcolor \
    xetex \
    zref

COPY ./img/* /resources/img/
COPY ./template/* /resources/templates/
COPY ./filter/* /resources/filters/

# mktexpk gets executed and needs a home dir, build one
RUN mkdir -m 0777 /home/user
ENV HOME="/home/user"

COPY ./filter/pandoc-crossref.yaml /home/user/.pandoc-crossref/config.yaml

COPY build.sh /usr/bin/build.sh

# Do a dry-run PDF render to warm up the TeX Live font cache.
COPY latex/fontcache.md /
# RUN /usr/bin/build.sh --nogitversion --pdf=fontcache.pdf /fontcache.md && rm /fontcache.md /fontcache.pdf

ENTRYPOINT ["/usr/bin/build.sh"]
CMD ["--help"]
