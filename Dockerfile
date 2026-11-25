FROM --platform=$BUILDPLATFORM debian:trixie-slim AS base-build
ARG TARGETARCH
RUN if [ "$TARGETARCH" != "$(dpkg --print-architecture)" ]; then \
      dpkg --add-architecture $TARGETARCH; \
      CROSS=crossbuild-essential-$TARGETARCH; \
    fi \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    $CROSS \
    ca-certificates \
    wget

FROM base-build AS pjsip
RUN apt-get install -y --no-install-recommends \
    libbcg729-dev:$TARGETARCH \
    libgsm1-dev:$TARGETARCH \
    libopencore-amrnb-dev:$TARGETARCH \
    libopencore-amrwb-dev:$TARGETARCH \
    libopus-dev:$TARGETARCH \
    libpcap-dev:$TARGETARCH \
    libsamplerate0-dev:$TARGETARCH \
    libsrtp2-dev:$TARGETARCH \
    libssl-dev:$TARGETARCH \
    libvo-amrwbenc-dev:$TARGETARCH

WORKDIR /pjsip
ARG VERSION_PJSIP=2.18
RUN wget "https://github.com/pjsip/pjproject/archive/refs/tags/${VERSION_PJSIP}.tar.gz" -O - | tar xzf - --strip-components=1
COPY *.patch .
RUN for patch in *.patch; do patch -p1 < $patch; done
# Cross builds skip bcg729/AMR/SSL unless a --with prefix is given
RUN HOST=$(dpkg-architecture -a$TARGETARCH -qDEB_HOST_GNU_TYPE) \
  && ./configure --host=$HOST \
  --disable-shared \
  --with-bcg729=/usr \
  --with-opencore-amr=/usr \
  --with-opencore-amrwbenc=/usr \
  --with-ssl=/usr \
  --enable-libsamplerate \
  --with-external-gsm \
  --with-external-srtp \
  --disable-libwebrtc \
  --disable-sound \
  && make -j$(nproc) \
  && $HOST-strip pjsip-apps/bin/samples/*/pcaputil

FROM base-build AS silk
WORKDIR /silk
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      SILK_PLATFORM="ARM"; \
    else \
      SILK_PLATFORM="FLP"; \
    fi; \
  wget 'https://github.com/audiocodes/silk/archive/refs/heads/decoder.tar.gz' -O - | tar xzf - --strip-components=2 silk-decoder/SILK_SDK_SRC_${SILK_PLATFORM}_v1.0.9
# Not TOOLCHAIN_PREFIX: it enables 32-bit ARM asm, which breaks aarch64
RUN HOST=$(dpkg-architecture -a$TARGETARCH -qDEB_HOST_GNU_TYPE) \
  && make -j$(nproc) CC=$HOST-gcc CXX=$HOST-g++ AR=$HOST-ar RANLIB=$HOST-ranlib decoder

FROM debian:trixie-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  libbcg729-0 \
  libgsm1 \
  libopencore-amrnb0 \
  libopencore-amrwb0 \
  libopus0 \
  libpcap0.8 \
  libsamplerate0 \
  libsrtp2-1 \
  libssl3 \
  libvo-amrwbenc0 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=pjsip /pjsip/pjsip-apps/bin/samples/*/pcaputil /usr/bin
COPY --from=silk /silk/decoder /usr/bin/silk-decoder
