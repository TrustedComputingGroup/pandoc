# syntax=docker/dockerfile:1.3-labs
ARG RUSTBASE=rust:1.92.0-trixie
ARG BUILDBASE=trixie-20251208-slim
ARG RUNBASE=pandoc/core:3.8.3-debian

FROM ${RUSTBASE} AS build-typst

RUN cargo install --version 0.14.2 typst-cli

FROM ${BUILDBASE} AS build-texlive

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

ENV MIRROR=https://mirror.ctan.org/systems/texlive/tlnet/

# install texlive ourselves instead of relying on the pandoc docker images,
# so that we can control the cross-platform support (e.g., arm64 linux)
# This layer takes several minutes to build.
RUN export ARCH=$(cat /ARCH) && \
    wget "$MIRROR/install-tl-unx.tar.gz" && \
    tar xzvf ./install-tl-unx.tar.gz && \
    ./install-tl-*/install-tl -v --repository "${MIRROR}" --force-platform "${ARCH}" -s basic --no-interaction

RUN mkdir -p /texlivebins && cp -r /usr/local/texlive/*/* /texlivebins

FROM ${BUILDBASE} AS build-fonts

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

FROM ${BUILDBASE} AS build-latexdiff

RUN apt update && apt install -y \
    build-essential \
    wget \
    xz-utils

# Install latexdiff
# The CTAN package doesn't let us customize the install (e.g., support latexdiff-fast), so we build it here.
RUN wget https://github.com/ftilmann/latexdiff/releases/download/1.3.4/latexdiff-1.3.4.tar.gz && \
    tar -xzf latexdiff-1.3.4.tar.gz && \
    cd latexdiff-1.3.4 && \
    make install-fast

# Build's done. Copy what we need into the actual container for running.
FROM ${RUNBASE} AS run

ARG TARGETPLATFORM

RUN apt update && apt install -y \
    aasvg \
    xorg \
    xvfb \
    dbus \
    bash \
    default-jre \
    fontconfig \
    graphviz \
    imagemagick \
    libnss3 \
    librsvg2-bin \
    libsecret-1-0 \
    libxss1 \
    moreutils \
    nodejs \
    npm \
    openbox \
    rsync \
    sed \
    software-properties-common \
    wget \
    yq

# Install Chromium via custom repo
# https://askubuntu.com/questions/1204571/how-to-install-chromium-without-snap/1511695#1511695
RUN add-apt-repository ppa:xtradeb/apps -y && \
    apt update && \
    apt install -y chromium

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

RUN npm install --global --unsafe-perm puppeteer@24.34.0 imgur@2.5.0 @mermaid-js/mermaid-cli@11.12.0 typescript@5.9.3 pandiff@0.8.0

RUN wget -O /usr/share/plantuml.jar https://github.com/plantuml/plantuml/releases/download/v1.2025.10/plantuml-asl-1.2025.10.jar

# Important: /usr/local/texlive/bin/ paths come before other paths. We want to use the texlive we
# built above, not any that happen to have come along with our base image.
ENV PATH="/usr/local/texlive/bin/aarch64-linux:/usr/local/texlive/bin/x86_64-linux:${PATH}"

# Copy TeX Live and latexdiff
COPY --from=build-texlive /texlivebins /usr/local/texlive
COPY --from=build-latexdiff /usr/local/bin/latexdiff* /usr/local/bin

# Packages that are needed despite not being used explicitly by the template:
# bigfoot, catchfile, fancyvrb, footmisc, framed, hardwrap, lineno, ltablex, latexmk, needspace, pgf, zref
# Package dependencies introduced by latexdiff:
# changebar, datetime2, latexdiff, listings, marginnote, pdfcomment, soulpos
RUN tlmgr update --self --all && tlmgr install \
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
    framed \
    fvextra \
    geometry \
    hardwrap \
    hyperref \
    hyphenat \
    koma-script \
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
    pdfcol \ 
    pagecolor \
    pdfcomment \
    pdflscape \
    pgf \
    polyglossia \
    ragged2e \
    selnolig \
    setspace \
    soulpos \
    tcolorbox \
    textpos \
    titling \
    tikzfill \
    ulem \
    unicode-math \
    upquote \
    varwidth \
    wrapfig \
    xcolor \
    xetex \
    xltabular \
    zref

ENV DRAWIO_RELEASE=29.2.9

# TARGETPLATFORM is linux/arm64 or linux/amd64. The release for amd64 is called drawio-amd64-23.1.5.deb.
RUN export DRAWIO_DEB=drawio-${TARGETPLATFORM#linux/}-${DRAWIO_RELEASE}.deb && \
    wget https://github.com/jgraph/drawio-desktop/releases/download/v${DRAWIO_RELEASE}/${DRAWIO_DEB} && \
    dpkg -i ${DRAWIO_DEB} && \
    rm ${DRAWIO_DEB}

# Copy Typst
COPY --from=build-typst /usr/local/cargo/bin/typst /usr/local/bin

# Copy only the fonts we're using from the template.
COPY --from=build-fonts \
    /usr/share/fonts/truetype/msttcorefonts/Arial* \
    /usr/share/fonts/truetype/msttcorefonts/Courier* \
    /usr/share/fonts/TTF/ARIAL* \
    /usr/share/fonts/OTF/Libertinus* \
    /usr/share/fonts/truetype/noto/NotoSans-* \
    /usr/share/fonts/truetype/noto/NotoSansMono-* \
    /usr/share/fonts/truetype/noto/NotoSansMath-* \
    /usr/share/fonts/truetype/noto/NotoSerif-* \
    /usr/share/fonts/
# Refresh the font cache.
RUN fc-cache -f

# https://stackoverflow.com/questions/52998331/imagemagick-security-policy-pdf-blocking-conversion
RUN sed -i '/disable ghostscript format types/,+6d' /etc/ImageMagick-6/policy.xml

COPY ./img/* /resources/img/
COPY ./template/* /resources/templates/
COPY ./filter/* /resources/filters/

# mktexpk gets executed and needs a home dir, build one
RUN mkdir -m 0777 /home/user
ENV HOME="/home/user"
ENV DBUS_SESSION_BUS_ADDRESS="unix:path=/var/run/dbus/system_bus_socket"

COPY ./filter/pandoc-crossref-iso.yaml /home/user/.pandoc-crossref/config.yaml
COPY ./filter/pandoc-crossref-tcg.yaml /home/user/.pandoc-crossref/config-tcg.yaml

COPY build.sh /usr/bin/build.sh

# Do a dry-run PDF render to warm up the TeX Live font cache.
# Currently this is disabled because of lack of evidence that it helps.
# COPY latex/fontcache.md /
# RUN /usr/bin/build.sh --nogitversion --pdf=fontcache.pdf /fontcache.md && rm /fontcache.md /fontcache.pdf

ENTRYPOINT ["/usr/bin/build.sh"]
CMD ["--help"]
