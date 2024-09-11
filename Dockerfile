# syntax=docker/dockerfile:1.3-labs
ARG BASE=debian:bookworm-20240812-slim
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

ENV PANDOC_CLI_VERSION=3.3
ENV PANDOC_CROSSREF_VERSION=0.3.17.1

RUN cabal update && \
    cabal install -j --only-dependencies \
    pandoc-cli-${PANDOC_CLI_VERSION} \
    pandoc-crossref-${PANDOC_CROSSREF_VERSION}

# Clone the source code associated with the target version of pandoc.
RUN git clone --branch=${PANDOC_CLI_VERSION} --depth=1 --quiet \
    https://github.com/jgm/pandoc /usr/src/pandoc

# Initialize a cabal.project file with the correct flags, and pin pandoc-crossref to its target.
RUN cat <<EOF > /usr/src/pandoc/cabal.project
packages: .
          pandoc-cli
extra-packages: pandoc-crossref == ${PANDOC_CROSSREF_VERSION}
flags: +embed_data_files +lua -server
EOF

# Compile the actual pandoc binaries.
RUN cabal build -j \
    --disable-tests \
    --disable-bench \
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
    xfonts-utils \
    xz-utils

# Install Arial via ttf-mscorefonts
RUN wget http://ftp.us.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.8.1_all.deb
RUN apt install -y cabextract
RUN dpkg -i ttf-mscorefonts-installer_3.8.1_all.deb

# Install the Arial Unicode MS font as well
RUN wget https://github.com/kaienfr/Font/raw/master/font/ARIALUNI.TTF -P /usr/share/fonts/TTF/

# Install Noto Sans Mono
RUN apt install -y fonts-noto

# Install Libertinus Math
RUN wget https://github.com/alerque/libertinus/releases/download/v7.040/Libertinus-7.040.tar.xz && \
    tar -xJf Libertinus-7.040.tar.xz && \
    mkdir -p /usr/share/fonts/OTF/ && \
    cp Libertinus-7.040/static/OTF/*.otf /usr/share/fonts/OTF/

# Build's done. Copy what we need into the actual container for running.
FROM ${BASE} as run

ARG TARGETPLATFORM

# These binaries are by far the most costly part of the build. Grab them first to minimize invalidation.
COPY --from=build-pandoc /pandocbins /usr/local/bin

# These binaries are the second most costly part of the build.
COPY --from=build-texlive /texlivebins /usr/local/texlive

# Copy only the fonts we're using from the template.
COPY --from=build-fonts \
    /usr/share/fonts/truetype/msttcorefonts/Arial* \
    /usr/share/fonts/TTF/ARIAL* \
    /usr/share/fonts/OTF/Libertinus* \
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

RUN npm install --global --unsafe-perm puppeteer@23.2.1 imgur@2.4.2 @mermaid-js/mermaid-cli@11.1.1 typescript@5.5.4 pandiff@0.6.0

# Important: /usr/local/texlive/bin/ paths come before other paths. We want to use the texlive we
# built above, not any that happen to have come along with our base image.
ENV PATH="/usr/local/texlive/bin/aarch64-linux:/usr/local/texlive/bin/x86_64-linux:${PATH}"

# Packages that are needed despite not being used explicitly by the template:
# bigfoot, catchfile, fancyvrb, footmisc, hardwrap, lineno, ltablex, latexmk, needspace, pgf, zref
# Package dependencies introduced by latexdiff:
# changebar, datetime2, latexdiff, listings, marginnote, pdfcomment, soulpos
RUN tlmgr update --self && tlmgr install \
    accsupp \
    adjustbox \
    appendix \
    amsmath \
    anyfontsize \
    adjustbox \
    anyfontsize \
    appendix \
    bigfoot \
    bookmark \
    booktabs \
    caption \
    catchfile \
    changebar \
    datetime2 \
    draftwatermark \
    enumitem \
    etoolbox \
    fancyhdr \
    fancyvrb \
    float \
    fontspec \
    footmisc \
    footnotebackref \
    footnotehyper \
    fvextra \
    geometry \
    hardwrap \
    hyperref \
    hyphenat \
    koma-script \
    latexdiff \
    latexmk \
    lineno \
    listings \
    ltablex \
    lualatex-math \
    luatex \
    luatex85 \
    luatexbase \
    makecell \
    marginnote \
    mathtools \
    mdframed \
    microtype \
    multirow \
    needspace \
    newunicodechar \
    pagecolor \
    pdfcomment \
    pdflscape \
    pgf \
    polyglossia \
    ragged2e \
    selnolig \
    setspace \
    soulpos \
    textpos \
    titling \
    ulem \
    unicode-math \
    upquote \
    varwidth \
    xcolor \
    xetex \
    xltabular \
    zref

RUN apt install -y \
    dbus \
    imagemagick \
    libxss1 \
    openbox \
    wget \
    xorg \
    xvfb

ENV DRAWIO_RELEASE=24.7.8

# TARGETPLATFORM is linux/arm64 or linux/amd64. The release for amd64 is called drawio-amd64-23.1.5.deb.
RUN export DRAWIO_DEB=drawio-${TARGETPLATFORM#linux/}-${DRAWIO_RELEASE}.deb && \
    wget https://github.com/jgraph/drawio-desktop/releases/download/v${DRAWIO_RELEASE}/${DRAWIO_DEB} && \
    dpkg -i ${DRAWIO_DEB} && \
    rm ${DRAWIO_DEB}

# https://stackoverflow.com/questions/52998331/imagemagick-security-policy-pdf-blocking-conversion
RUN sed -i '/disable ghostscript format types/,+6d' /etc/ImageMagick-6/policy.xml

COPY ./img/* /resources/img/
COPY ./template/* /resources/templates/
COPY ./filter/* /resources/filters/

# mktexpk gets executed and needs a home dir, build one
RUN mkdir -m 0777 /home/user
ENV HOME="/home/user"
ENV DBUS_SESSION_BUS_ADDRESS="unix:path=/var/run/dbus/system_bus_socket"

COPY ./filter/pandoc-crossref.yaml /home/user/.pandoc-crossref/config.yaml

COPY build.sh /usr/bin/build.sh

# Do a dry-run PDF render to warm up the TeX Live font cache.
# Currently this is disabled because of lack of evidence that it helps.
# COPY latex/fontcache.md /
# RUN /usr/bin/build.sh --nogitversion --pdf=fontcache.pdf /fontcache.md && rm /fontcache.md /fontcache.pdf

ENTRYPOINT ["/usr/bin/build.sh"]
CMD ["--help"]
