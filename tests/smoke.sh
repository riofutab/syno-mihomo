#!/usr/bin/env bash
# 在 Linux 上模拟群晖安装流程，验证 spk 的结构和容器的实际功能。
# 需要 sudo（创建 /var/packages/syno-mihomo）、docker、curl、jq。
#
# 用法: tests/smoke.sh <spk 文件> <x86_64|armv8>
set -euo pipefail

SPK="${1:?用法: smoke.sh <spk 文件> <架构>}"
ARCH="${2:?缺少架构}"
PKG_ROOT=/var/packages/syno-mihomo
WORK="$(mktemp -d)"
COMPOSE=(docker compose -p syno-mihomo -f "$PKG_ROOT/target/mihomo/compose.yaml")

cleanup() {
    "${COMPOSE[@]}" logs --no-color 2>/dev/null | tail -n 80 || true
    "${COMPOSE[@]}" down 2>/dev/null || true
    sudo rm -rf "$PKG_ROOT" "$WORK"
}
trap cleanup EXIT

fail() { echo "失败: $*" >&2; exit 1; }
pass() { echo "通过: $*"; }

# ---- 结构 ----
tar -xf "$SPK" -C "$WORK"
for f in INFO package.tgz scripts/start-stop-status scripts/postinst conf/privilege conf/resource PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG; do
    [ -e "$WORK/$f" ] || fail "spk 里缺少 $f"
done
grep -qx "arch=\"$ARCH\"" "$WORK/INFO" || fail "INFO 的 arch 不是 $ARCH"
want="$(sed -n 's/^checksum="\(.*\)"$/\1/p' "$WORK/INFO")"
[ "$want" = "$(md5sum "$WORK/package.tgz" | cut -d' ' -f1)" ] || fail "INFO 里的 checksum 与 package.tgz 不一致"
jq -e . "$WORK/conf/resource" "$WORK/conf/privilege" >/dev/null || fail "conf 不是合法 JSON"
[ -x "$WORK/scripts/start-stop-status" ] || fail "脚本没有执行权限"
pass "spk 结构"

# ---- 模拟安装：解压到 target，载入镜像，执行 postinst ----
sudo mkdir -p "$PKG_ROOT/target" "$PKG_ROOT/var"
sudo tar -xzf "$WORK/package.tgz" -C "$PKG_ROOT/target"
sudo chown "$(id -u):$(id -g)" "$PKG_ROOT/var"
jq -e . "$PKG_ROOT/target/ui/config" >/dev/null || fail "ui/config 不是合法 JSON"
gunzip -c "$PKG_ROOT/target/image.tar.gz" | docker load
SYNOPKG_PKGVAR="$PKG_ROOT/var" SYNOPKG_TEMP_LOGFILE="$WORK/install.log" sh "$WORK/scripts/postinst"
grep -qE '^http://[0-9.]+:7881$' "$PKG_ROOT/var/backend_url" || fail "postinst 没有写出 backend_url"
pass "模拟安装"

# ---- 启动 ----
"${COMPOSE[@]}" up -d
for _ in $(seq 1 60); do
    curl -fsS http://127.0.0.1:7880/api/control/health >/dev/null 2>&1 && break
    sleep 2
done
curl -fsS http://127.0.0.1:7880/api/control/health >/dev/null || fail "面板 7880 没有启动"
pass "面板 7880"

config_js="$(curl -fsS http://127.0.0.1:7880/config.js)"
TOKEN="$(sed -n 's/.*"controlToken":"\([^"]*\)".*/\1/p' <<<"$config_js")"
[ "${#TOKEN}" -eq 48 ] || fail "面板没有拿到 CONTROL_TOKEN"
grep -q "\"defaultBackendURL\":\"$(cat "$PKG_ROOT/var/backend_url")\"" <<<"$config_js" || fail "面板没有拿到默认后端地址"
pass "CONTROL_TOKEN 和默认后端地址已注入"

for _ in $(seq 1 30); do
    curl -fsS http://127.0.0.1:7881/version >/dev/null 2>&1 && break
    sleep 2
done
curl -fsS http://127.0.0.1:7881/version || fail "mihomo 控制接口 7881 不通"
echo
pass "mihomo 控制接口 7881"

# ---- 导入一份和真实订阅设置相同的配置：打开 TUN、DNS 监听 53、external-controller 只听本机 ----
api() { curl -fsS -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$@"; }
content="$(cat tests/fixtures/subscription.yaml)"
id="$(api -X POST http://127.0.0.1:7880/api/control/profiles \
    -d "$(jq -n --arg c "$content" '{name: "smoke", type: "local", content: $c}')" | jq -r .id)"
[ -n "$id" ] && [ "$id" != null ] || fail "创建配置失败"
api -X POST "http://127.0.0.1:7880/api/control/profiles/$id/activate" | jq -c .
echo
sleep 5
curl -fsS http://127.0.0.1:7881/version >/dev/null || fail "导入带 TUN 的配置后，mihomo 控制接口不通"
pass "导入带 TUN 的配置后 mihomo 仍在运行"

# ---- 代理 ----
TARGET=https://www.gstatic.com/generate_204
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -x http://127.0.0.1:7890 "$TARGET")"
[ "$code" = 204 ] || fail "HTTP 代理返回 $code"
pass "HTTP 代理 7890"
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --socks5-hostname 127.0.0.1:7890 "$TARGET")"
[ "$code" = 204 ] || fail "SOCKS5 代理返回 $code"
pass "SOCKS5 代理 7890"

# ---- 端口只绑 IPv4 ----
if ss -Hltn | grep -E '\[::\]:(7880|7881|7890)\b'; then
    fail "端口绑定到了 IPv6"
fi
pass "端口只绑定 IPv4"

echo "全部通过"
