#!/bin/sh
# 在官方入口之前补两项环境变量，然后交给官方入口启动。
set -eu

mkdir -p "$DATA_DIR"

# CONTROL_TOKEN 不设置时，面板的内核和订阅管理接口返回 503。
# 首次启动随机生成并保存在数据目录，之后沿用。
token_file="$DATA_DIR/.control_token"
if [ ! -s "$token_file" ]; then
    (umask 077 && tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48 >"$token_file")
fi
CONTROL_TOKEN=$(cat "$token_file")
export CONTROL_TOKEN

# postinst 写入的 NAS 地址。面板首次打开时用它自动连接 mihomo，不用手填。
if [ -s /pkgvar/backend_url ]; then
    DEFAULT_BACKEND_URL=$(cat /pkgvar/backend_url)
    export DEFAULT_BACKEND_URL
fi

exec /docker-entrypoint.sh
