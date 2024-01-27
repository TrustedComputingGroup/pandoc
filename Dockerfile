FROM debian:bookworm-20240110-slim as build

# use --build-arg ARCH=aarch64-linux for arm64
ARG ARCH=x86_64-linux

RUN echo "Building for ${ARCH}"

# fun fact: if curl is not present, install-tl will fail even though it claims to fall back to wget.
# TODO: Remove as many packages as possible from here and add them to a later package upgrade step.
# Ideally, this Dockerfile will be organized such that very long-running tasks that are infrequently
# modified are all up at the top.
RUN apt update && apt install -y \
    bash \
    chromium \
    coreutils \
    curl \
    git \
    nodejs \
    npm \
    perl \
    python3 \
    python3-pandocfilters \
    sed \
    wget \
    yarn

ENV MIRROR=https://mirror.ctan.org/systems/texlive/tlnet/

WORKDIR /texlive

# install texlive ourselves instead of relying on the pandoc docker images,
# so that we can control the cross-platform support (e.g., arm64 linux)
# This layer takes several minutes to build.
RUN wget "$MIRROR/install-tl-unx.tar.gz" && \
    tar xzvf ./install-tl-unx.tar.gz && \
    ./install-tl-*/install-tl -v --force-platform "${ARCH}" -s basic --no-interaction && \
    cd / && \
    rm -rf /texlive

WORKDIR /usr/src/pandoc

# Install pandoc and pandoc-crossref
RUN apt install -y \
    cabal-install \
    g++ \
    pkg-config \
    zlib1g \
    zlib1g-dev

ENV PANDOC_REF=3.1.11.1
RUN git clone --branch=${PANDOC_REF} --depth=1 --quiet \
  https://github.com/jgm/pandoc /usr/src/pandoc

# Replace the default project config from the Pandoc repo.
COPY ./pandoc/cabal.project /usr/src/pandoc/cabal.project

# This layer takes several minutes to build.
RUN cabal v2-update \
  && cabal v2-build -j \
      --allow-newer 'lib:pandoc' \
      --disable-tests \
      --disable-bench \
      --jobs \
      . pandoc-cli pandoc-crossref

# Copy just the binaries we want into /usr/local/bin.
RUN mkdir -p /pandocbins && \
    find dist-newstyle \
    -name 'pandoc*' -type f -perm -u+x \
    -exec strip '{}' ';' \
    -exec cp '{}' /pandocbins/ ';'

WORKDIR /

# Install arial via ttf-mscorefonts
RUN wget http://ftp.us.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.8.1_all.deb
RUN apt install -y cabextract xfonts-utils
RUN dpkg -i ttf-mscorefonts-installer_3.8.1_all.deb && \
    fc-cache -f

# Install the Arial Unicode MS font as well
RUN wget https://github.com/kaienfr/Font/raw/master/font/ARIALUNI.TTF -P /usr/share/fonts/TTF/ && \
    fc-cache -f

# Install Noto Sans Mono
RUN apt install -y fonts-noto && \
    fc-cache -f

RUN mkdir -p /texlivebins && cp -r /usr/local/texlive/*/* /texlivebins

# Build's done. Copy what we need into the actual container for running.
FROM debian:bookworm-20240110-slim as run
ARG ARCH

RUN apt update && apt install -y \
    bash \
    chromium \
    coreutils \
    nodejs \
    npm \
    perl \
    python3 \
    python3-pandocfilters \
    sed \
    yarn

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

RUN npm install --global --unsafe-perm puppeteer@21.7.0 imgur@2.3.0 mermaid-filter@1.4.7 typescript@5.3.3 pandiff@0.6.0

COPY --from=build /texlivebins /usr/local/texlive

ENV PATH="${PATH}:/usr/local/texlive/bin/${ARCH}"

# Packages that are needed despite not being used explicitly by the template:
# catchfile, fancyvrb, hardwrap, lineno, lualatex-math, luatexspace, needspace, pgf, zref
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
    csquotes \
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
    pagecolor \
    pdflscape \
    pgf \
    polyglossia \
    ragged2e \
    selnolig \
    setspace \
    tex-gyre \
    textpos \
    titling \
    transparent \
    unicode-math \
    upquote \
    xcolor \
    zref

COPY --from=build /pandocbins /usr/local/bin

# Copy only the fonts we're using from the template.
COPY --from=build /usr/share/fonts/truetype/msttcorefonts/Arial* /usr/share/fonts/truetype/msttcorefonts/
COPY --from=build /usr/share/fonts/TTF/ARIAL* /usr/share/fonts/TTF/
COPY --from=build /usr/share/fonts/truetype/noto/NotoSansMono* /usr/share/fonts/truetype/noto/

# Packages that are needed despite not being used explicitly by the template:
# catchfile, hardwrap, lineno, needspace, zref
RUN tlmgr update --self && tlmgr install \
    accsupp \
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
