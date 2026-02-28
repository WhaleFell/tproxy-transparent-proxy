FROM alpine:latest AS builder

ARG HTTP_PROXY
ARG HTTPS_PROXY

WORKDIR /build

RUN apk add --no-cache ca-certificates curl gzip unzip && update-ca-certificates

RUN set -eux; \
    # Download and normalize mihomo executable.
    # 下载并规范化 mihomo 可执行文件。
    MIHOMO_ASSET_URL="$(curl -fsSL https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep -Eo 'https://[^"]*mihomo-linux-amd64-compatible-v[^"]*\.gz' | head -n1)"; \
    test -n "${MIHOMO_ASSET_URL}"; \
    curl -fL --retry 3 -o mihomo.gz "${MIHOMO_ASSET_URL}"; \
    mkdir -p /tmp/mihomo_extract; \
    # Support both tar.gz and plain gz payload format.
    # 同时兼容 tar.gz 与纯 gz 两种压缩格式。
    if tar -xzf mihomo.gz -C /tmp/mihomo_extract 2>/dev/null; then \
      true; \
    else \
      gzip -dc mihomo.gz > /tmp/mihomo_extract/mihomo.bin; \
    fi; \
    MIHOMO_BIN_COUNT="$(find /tmp/mihomo_extract -type f | sed '/^$/d' | wc -l)"; \
    test "${MIHOMO_BIN_COUNT}" -eq 1; \
    MIHOMO_BIN_PATH="$(find /tmp/mihomo_extract -type f | head -n1)"; \
    install -m 0755 "${MIHOMO_BIN_PATH}" mihomo; \
    ./mihomo -v; \
    # Download data files.
    # 下载数据文件。
    curl -fL --retry 3 -o GeoIP.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat; \
    curl -fL --retry 3 -o GeoSite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat; \
    # Download and extract dashboard UI.
    # 下载并解压 dashboard UI。
    mkdir -p ui; \
    curl -fL --retry 3 -o zashboard.zip https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip; \
    unzip -q zashboard.zip; \
    mv zashboard-gh-pages ui/zashboard; \
    # Cleanup build cache files to reduce intermediate layer size.
    # 清理构建阶段临时文件，减小中间层体积。
    rm -rf /tmp/mihomo_extract mihomo.gz zashboard.zip

FROM alpine:latest

WORKDIR /mihomo

RUN set -eux; \
    apk add --no-cache ca-certificates tzdata nftables iproute2; \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    echo "Asia/Shanghai" > /etc/timezone; \
    # Keep timezone files but remove tzdata package to reduce runtime size.
    # 保留时区配置后移除 tzdata 包，减小运行镜像体积。
    apk del tzdata; \
    update-ca-certificates

ENV TZ=Asia/Shanghai

# Clean runtime proxy variables to avoid leaking build proxy into production.
# 清理运行时代理变量，避免构建代理泄漏到生产环境。
ENV HTTP_PROXY= \
    HTTPS_PROXY= \
    http_proxy= \
    https_proxy=

COPY --from=builder --chmod=755 /build/mihomo /usr/bin/mihomo
COPY --from=builder /build/GeoIP.dat /usr/share/mihomo-defaults/GeoIP.dat
COPY --from=builder /build/GeoSite.dat /usr/share/mihomo-defaults/GeoSite.dat
COPY --from=builder /build/ui/zashboard /usr/share/mihomo-defaults/ui/zashboard
COPY nftables.rules /etc/nftables.rules
COPY --chmod=755 entrypoint.sh /usr/bin/entrypoint.sh

ENTRYPOINT ["/usr/bin/entrypoint.sh"]
CMD ["/usr/bin/mihomo", "-d", "/mihomo/", "-f", "/mihomo/config/config.yaml"]
