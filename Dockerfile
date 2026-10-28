# ================================
# Build image
# ================================
FROM swift:6.2-noble AS build

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y libjemalloc-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Resolve dependencies first so this layer is cached between source changes
COPY ./Package.* ./
RUN swift package resolve \
        $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

COPY . .

RUN swift build -c release \
        --product RoomsServer \
        --static-swift-stdlib \
        -Xlinker -ljemalloc

WORKDIR /staging

RUN cp "$(swift build --package-path /build -c release --show-bin-path)/RoomsServer" ./
RUN find -L "$(swift build --package-path /build -c release --show-bin-path)/" -regex '.*\.resources$' -exec cp -Ra {} ./ \;

# ================================
# Run image
# ================================
FROM ubuntu:noble

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      tzdata \
      libsqlite3-0 \
    && rm -r /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

WORKDIR /app

COPY --from=build --chown=vapor:vapor /staging /app

ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

USER vapor:vapor

# Railway provides PORT, it is read by `configure(_:)`
EXPOSE 8080

ENTRYPOINT ["./RoomsServer"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0"]
