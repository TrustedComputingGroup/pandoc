ARG BASE=debian:bookworm-20240110-slim
ARG RUN_BASE=gcr.io/distroless/nodejs20-debian12
ARG DEBUG
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
    libfontconfig \
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

# Lazy: Just put both possible texlive paths into the path. Only one will get populated.
ENV PATH="${PATH}:/usr/local/texlive/2023/bin/x86_64-linux:/usr/local/texlive/2023/bin/aarch64-linux"

# Packages that are needed despite not being used explicitly by the template:
# catchfile, fancyvrb, hardwrap, lineno, ltablex, latexmk, needspace, pgf, zref
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
    latexmk \
    lineno \
    ltablex \
    makecell \
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
    unicode-math \
    upquote \
    varwidth \
    xcolor \
    xetex \
    xltabular \
    zref

FROM ${BASE} as build-fonts

RUN apt update && apt install -y \
    fontconfig \
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

RUN fc-cache -f

FROM ${BASE} as build-node-dependencies

RUN apt update && apt install -y \
    npm

# Misc dependencies we will install with apt then copy for minimal container size
FROM ${BASE} as build-other

RUN apt update && apt install -y \
    bash \
    chromium \
    git \
    imagemagick \
    libpng-dev \
    librsvg2-bin \
    ltrace \
    moreutils \
    npm \
    perl \
    strace \
    sed

# Build's done. Copy what we need into the actual container for running.
FROM ${RUN_BASE} as run
ARG DEBUG

# These binaries are by far the most costly part of the build. Grab them first
# to minimize invalidation in cases where layers of this stage are cached but
# not layers of other stages (i.e., GitHub CI).
COPY --from=build-pandoc /pandocbins /usr/local/bin

# These binaries are the second most costly part of the build. Grab them next.
COPY --from=build-texlive /usr/local/texlive /usr/local/texlive
COPY --from=build-texlive \
    /usr/local/texlive/*/bin/*/latexmk \
    /usr/local/bin/

# Copy only the fonts we're using from the template.
COPY --from=build-fonts \
    /usr/share/fonts/truetype/msttcorefonts/Arial* \
    /usr/share/fonts/TTF/ARIAL* \
    /usr/share/fonts/truetype/noto/NotoSansMono* \
    /usr/share/fonts/

# Copy misc other binaries we need
COPY --from=build-other \
    /usr/bin/basename \
    /usr/bin/cat \
    /usr/bin/cp \
    /usr/bin/chromium \
    /usr/bin/convert \
    /usr/bin/cut \
    /usr/bin/date \
    /usr/bin/dirname \
    /usr/bin/env \
    /usr/bin/grep \
    /usr/bin/getopt \
    /usr/bin/git \
    /usr/bin/ls \
    /usr/bin/ltrace \
    /usr/bin/mkdir \
    /usr/bin/mv \
    /usr/bin/node \
    /usr/bin/npm \
    /usr/bin/rm \
    /usr/bin/perl \
    /usr/bin/rsvg-convert \
    /usr/bin/sed \
    /usr/bin/strace \
    /usr/bin/tail \
    /usr/bin/ts \
    /usr/bin/which \
    /usr/bin
COPY --from=build-other \
    /bin/bash \
    /bin/sh \
    /bin/
COPY --from=build-other \
    /etc/ImageMagick-6/* \
    /etc/ImageMagick-6/

# Copy all the shared libraries we need.
# A useful one-liner for working on this list:
# ltrace -l '*' $(your command goes here) | grep .so | awk 'BEGIN {FS="->";}{print $1}' | uniq | sort | uniq
COPY --from=build-other \
    /lib/*/libacl.so* \
    /lib/*/libattr.so* \
    /lib/*/libblkid.so* \
    /lib/*/libbrotlicommon.so* \
    /lib/*/libbrotlidec.so* \
    /lib/*/libbrotlienc.so* \
    /lib/*/libbsd.so* \
    /lib/*/libbz*.so* \
    /lib/*/libc.so* \
    /lib/*/libcairo.so* \
    /lib/*/libcares.so* \
    /lib/*/libcrypt.so* \
    /lib/*/libdatrie.so* \
    /lib/*/libexpat.so* \
    /lib/*/libffi.so* \
    /lib/*/libfftw*.so* \
    /lib/*/libfontconfig.so* \
    /lib/*/libfreetype.so* \
    /lib/*/libfribidi.so* \
    /lib/*/libgdk_pixbuf*.so* \
    /lib/*/libgio-*.so* \
    /lib/*/libglib-*.so* \
    /lib/*/libgmodule-*.so* \
    /lib/*/libgmp.so* \
    /lib/*/libgobject-*.so* \
    /lib/*/libgraphite2.so* \
    /lib/*/libharfbuzz.so* \
    /lib/*/libicudata.so* \
    /lib/*/libicui18n.so* \
    /lib/*/libicuuc.so* \
    /lib/*/libjpeg.so* \
    /lib/*/liblcms*.so* \
    /lib/*/liblqr-*.so* \
    /lib/*/libltdl.so* \
    /lib/*/liblzma.so* \
    /lib/*/libMagickCore-*.so* \
    /lib/*/libMagickWand-*.so* \
    /lib/*/libmd.so* \
    /lib/*/libmount.so* \
    /lib/*/libnghttp2.so* \
    /lib/*/libnode.so* \
    /lib/*/libpango-*.so* \
    /lib/*/libpangocairo-*.so* \
    /lib/*/libpangoft2-*.so* \
    /lib/*/libpcre*.so* \
    /lib/*/libpixbufloader-svg.so* \
    /lib/*/libpixman-*.so* \
    /lib/*/libpng*.so* \
    /lib/*/librsvg*.so* \
    /lib/*/libselinux.so* \
    /lib/*/libstdc++.so* \
    /lib/*/libthai.so* \
    /lib/*/libtinfo.so* \
    /lib/*/libuv.so* \
    /lib/*/libX11.so* \
    /lib/*/libXau.so* \
    /lib/*/libxcb-render.so* \
    /lib/*/libxcb-shm.so* \
    /lib/*/libxcb.so* \
    /lib/*/libXdmcp.so* \
    /lib/*/libX11.so* \
    /lib/*/libXext.so* \
    /lib/*/libxml*.so* \
    /lib/*/libXrender.so* \
    /lib/*/libz.so* \
    /lib/
COPY --from=build-other \
    /usr/lib/x86_64-linux-gnu/ImageMagick-6.9.11/ \
    /usr/lib/x86_64-linux-gnu/ImageMagick-6.9.11/
COPY --from=build-other \
    /usr/lib/x86_64-linux-gnu/perl-base \
    /usr/lib/x86_64-linux-gnu/perl-base
COPY --from=build-other \
    /usr/lib/x86_64-linux-gnu/perl \
    /usr/lib/x86_64-linux-gnu/perl
COPY --from=build-other \
    /usr/share/perl/ \
    /usr/share/perl/

RUN npm install --global --unsafe-perm puppeteer@21.7.0 imgur@2.3.0 mermaid-filter@1.4.7 typescript@5.3.3 pandiff@0.6.0 pandoc-filter@2.2.0

COPY --from=build-fonts \
    /etc/fonts \
    /etc/fonts

ENV FONTCONFIG_PATH=/etc/fonts

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Lazy: Just put both possible texlive paths into the path. Only one will get populated.
ENV PATH="${PATH}:/usr/local/texlive/2023/bin/aarch64-linux:/usr/local/texlive/2023/bin/x86_64-linux"

# https://stackoverflow.com/questions/52998331/imagemagick-security-policy-pdf-blocking-conversion
RUN sed -i '/disable ghostscript format types/,+6d' /etc/ImageMagick-6/policy.xml

# Tools we only need in debug.
RUN if [[ -z "${DEBUG}" ]]; then rm \
    /usr/bin/ltrace \
    /usr/bin/strace \
    ; fi

COPY ./img/* /resources/img/
COPY ./template/* /resources/templates/
COPY ./filter/* /resources/filters/

# mktexpk gets executed and needs a home dir, build one
RUN mkdir -m 0777 /home/user
ENV HOME="/home/user"

COPY ./filter/pandoc-crossref.yaml /home/user/.pandoc-crossref/config.yaml

COPY build.sh /usr/bin/build.sh

# Do a dry-run PDF render to warm up the TeX Live font cache.
# Currently this is disabled because of lack of evidence that it helps.
# COPY latex/fontcache.md /
# RUN /usr/bin/build.sh --nogitversion --pdf=fontcache.pdf /fontcache.md && rm /fontcache.md /fontcache.pdf

ENTRYPOINT ["/bin/bash", "/usr/bin/build.sh"]
CMD ["--help"]
