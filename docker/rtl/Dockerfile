FROM debian:bookworm-slim

ARG OSS_CAD_SUITE_VERSION=2026-10-28
ARG OSS_CAD_SUITE_SHA256=5ed05e6e197cb1c98d079778a560f94ee04f7bc5fa09f2239bf30f032672e7f2

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl \
      g++ \
      make \
      python3 \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN curl --fail --location --retry 3 \
      "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${OSS_CAD_SUITE_VERSION}/oss-cad-suite-linux-x64-$(printf '%s' "$OSS_CAD_SUITE_VERSION" | tr -d '-').tgz" \
      --output /tmp/oss-cad-suite.tgz \
 && printf '%s  %s\n' "$OSS_CAD_SUITE_SHA256" /tmp/oss-cad-suite.tgz | sha256sum --check - \
 && tar -xzf /tmp/oss-cad-suite.tgz -C /opt \
 && rm /tmp/oss-cad-suite.tgz

ENV PATH="/opt/oss-cad-suite/bin:${PATH}"

WORKDIR /workspace
