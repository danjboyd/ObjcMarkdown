# ObjcMarkdown Linux CI image: the clang/libobjc2/libdispatch GNUstep stack
# the project targets (docs/linux-clang-toolchain.md), built the way GNUstep's
# tools-scripts clang flow builds it, into /usr/GNUstep, plus what the tests
# need (Xvfb, fonts, pandoc).
#
# Built and pushed by .github/workflows/ci-image.yml; the CI workflow runs in
# it, pinned by digest. Every source is pinned by commit, so the image only
# changes when these do.

FROM debian:trixie

# Upstream commits (2026-10-06). tools-make and libdispatch are the commits
# the authoring machine runs; libobjc2, base, gui and back are the official
# repositories' default branches; tools-xctest is danjboyd's fork, which
# the tests use (upstream's newest tag is v0.1.1).
ARG LIBOBJC2_COMMIT=fd475057c191ab64586679ffe5e46636776aecbe
ARG LIBDISPATCH_COMMIT=b2a1fad6b49a9394cf864b87ab0034ea8300e2de
ARG TOOLS_MAKE_COMMIT=04abaf7b23a0a2b8fdf3c819021f7d5d7b269688
ARG LIBS_BASE_COMMIT=68f3d75694f0a7edf9fb1c6c7f19582e8cff1b5f
ARG LIBS_GUI_COMMIT=549f639137a600936acde4cd618f0e4b858d883d
ARG LIBS_BACK_COMMIT=23fbe390dfa80c9eadf7174700de8553a985bc8f
ARG TOOLS_XCTEST_REPO=https://github.com/danjboyd/tools-xctest
ARG TOOLS_XCTEST_COMMIT=a9fe0b9aefd204ece0eb0d3aedcd7fa93878e65f

ENV DEBIAN_FRONTEND=noninteractive \
    CC=clang \
    CXX=clang++ \
    LDFLAGS=-fuse-ld=lld

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git curl make cmake ninja-build pkg-config \
        clang lld \
        libffi-dev libxml2-dev libxslt1-dev libgnutls28-dev libicu-dev \
        libcurl4-gnutls-dev zlib1g-dev \
        libjpeg-dev libtiff-dev libpng-dev libgif-dev \
        libcairo2-dev libfreetype-dev libfontconfig-dev libxft-dev \
        libx11-dev libxext-dev libxt-dev libxrandr-dev libxcursor-dev libxi-dev libxfixes-dev \
        xvfb xauth fonts-dejavu-core \
        pandoc \
    && rm -rf /var/lib/apt/lists/*

# Fetches one commit of a repository into /src/NAME.
COPY fetch-commit.sh /usr/local/bin/fetch-commit
RUN chmod 755 /usr/local/bin/fetch-commit
WORKDIR /src

# gnustep-make first: libobjc2 and libdispatch install where it says.
RUN fetch-commit https://github.com/gnustep/tools-make "$TOOLS_MAKE_COMMIT" tools-make \
    && cd tools-make \
    && CCFLAGS="-fblocks -fobjc-nonfragile-abi" ./configure --prefix=/usr/GNUstep \
         --with-library-combo=ng-gnu-gnu --enable-objc-arc --enable-native-objc-exceptions \
         --with-layout=gnustep \
    && make -j"$(nproc)" && make install \
    && ln -s /usr/GNUstep/System/Library/Makefiles/GNUstep.sh /etc/profile.d/GNUstep.sh

RUN . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh \
    && fetch-commit https://github.com/gnustep/libobjc2 "$LIBOBJC2_COMMIT" libobjc2 \
    && cmake -S libobjc2 -B libobjc2/build -G Ninja -DGNUSTEP_INSTALL_TYPE=SYSTEM -DTESTS=OFF \
         -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    && cmake --build libobjc2/build && cmake --install libobjc2/build && ldconfig

RUN . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh \
    && fetch-commit https://github.com/apple/swift-corelibs-libdispatch "$LIBDISPATCH_COMMIT" libdispatch \
    && cmake -S libdispatch -B libdispatch/build -G Ninja -DTESTS=OFF -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
         -DCMAKE_INSTALL_BINDIR="$(gnustep-config --variable=GNUSTEP_SYSTEM_TOOLS)" \
         -DCMAKE_INSTALL_LIBDIR="$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARIES)" \
         -DCMAKE_INSTALL_INCLUDEDIR="$(gnustep-config --variable=GNUSTEP_SYSTEM_HEADERS)" \
         -DCMAKE_INSTALL_MANDIR="$(gnustep-config --variable=GNUSTEP_SYSTEM_DOC_MAN)" \
         -DCMAKE_INSTALL_DATAROOTDIR="$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARY)" \
    && cmake --build libdispatch/build && cmake --install libdispatch/build && ldconfig

RUN . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh \
    && fetch-commit https://github.com/gnustep/libs-base "$LIBS_BASE_COMMIT" libs-base \
    && cd libs-base && ./configure \
    && make -j"$(nproc)" LDFLAGS="$LDFLAGS -ldispatch" GNUSTEP_INSTALLATION_DOMAIN=SYSTEM \
    && make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install && ldconfig

RUN . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh \
    && fetch-commit https://github.com/gnustep/libs-gui "$LIBS_GUI_COMMIT" libs-gui \
    && cd libs-gui && ./configure \
    && make -j"$(nproc)" GNUSTEP_INSTALLATION_DOMAIN=SYSTEM \
    && make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install && ldconfig

RUN . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh \
    && fetch-commit https://github.com/gnustep/libs-back "$LIBS_BACK_COMMIT" libs-back \
    && cd libs-back && ./configure \
    && make -j"$(nproc)" GNUSTEP_INSTALLATION_DOMAIN=SYSTEM \
    && make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install && ldconfig

RUN . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh \
    && fetch-commit "$TOOLS_XCTEST_REPO" "$TOOLS_XCTEST_COMMIT" tools-xctest \
    && cd tools-xctest \
    # Serial: its XCTestHost library links -lXCTest, built alongside it.
    && make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM \
    && make GNUSTEP_INSTALLATION_DOMAIN=SYSTEM install && ldconfig \
    && rm -rf /src

# What the image was built from, for logs and release notes.
RUN printf 'libobjc2 %s\nlibdispatch %s\ntools-make %s\nlibs-base %s\nlibs-gui %s\nlibs-back %s\ntools-xctest %s %s\n' \
        "$LIBOBJC2_COMMIT" "$LIBDISPATCH_COMMIT" "$TOOLS_MAKE_COMMIT" "$LIBS_BASE_COMMIT" \
        "$LIBS_GUI_COMMIT" "$LIBS_BACK_COMMIT" "$TOOLS_XCTEST_REPO" "$TOOLS_XCTEST_COMMIT" \
        > /usr/GNUstep/ci-toolchain.txt

WORKDIR /
