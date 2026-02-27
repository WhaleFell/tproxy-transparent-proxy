#!/bin/sh
set -eu

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# Ensure no runtime proxy variables affect startup behavior.
# 确保运行时代理变量不会影响启动行为。
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy

# Prepare routing policy for TPROXY mark 1 traffic.
# 为 TPROXY 的 mark=1 流量准备策略路由。
if ! ip rule show 2>/dev/null | grep -q 'fwmark 0x1 lookup 100'; then
  ip rule add fwmark 1 table 100
  log "Added IPv4 policy rule: fwmark 1 -> table 100"
fi

if ! ip -6 rule show 2>/dev/null | grep -q 'fwmark 0x1 lookup 106'; then
  ip -6 rule add fwmark 1 table 106
  log "Added IPv6 policy rule: fwmark 1 -> table 106"
fi

if ! ip route show table 100 2>/dev/null | grep -q 'local 0.0.0.0/0 dev lo'; then
  ip route add local 0.0.0.0/0 dev lo table 100
  log "Added IPv4 local route in table 100"
fi

if ! ip -6 route show table 106 2>/dev/null | grep -q 'local ::/0 dev lo'; then
  ip -6 route add local ::/0 dev lo table 106
  log "Added IPv6 local route in table 106"
fi

# Apply nftables rules before starting mihomo.
# 在启动 mihomo 前加载 nftables 规则。
if ! nft -f /mihomo/nftables.rules; then
  log "Failed to load nftables rules."
  log "Please ensure host kernel supports nft socket/tproxy modules: nft_socket, nft_tproxy, nf_socket_ipv4, nf_socket_ipv6, nf_tproxy_ipv4, nf_tproxy_ipv6."
  log "nftables 规则加载失败，请确认宿主机内核已启用/加载 nft socket/tproxy 相关模块。"
  exit 1
fi
log "Loaded nftables rules from /mihomo/nftables.rules"

CONFIG_FILE=""
if [ -f /mihomo/config.yaml ]; then
  CONFIG_FILE="/mihomo/config.yaml"
elif [ -f /mihomo/config/config.yaml ]; then
  CONFIG_FILE="/mihomo/config/config.yaml"
fi

# Validate configuration if config file exists.
# 若配置文件存在，则先执行配置校验。
if [ -n "${CONFIG_FILE}" ]; then
  log "Found config file: ${CONFIG_FILE}. Validating..."
  if ! /mihomo/mihomo -t -d /mihomo; then
    log "Configuration validation failed. Exit."
    exit 1
  fi
  log "Configuration validation passed."
else
  log "No config file found at /mihomo/config.yaml or /mihomo/config/config.yaml. Skip validation."
fi

log "Starting mihomo..."
exec "$@"
