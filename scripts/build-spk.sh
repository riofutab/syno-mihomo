#!/usr/bin/env bash
# 组装群晖套件（.spk）。需要 Linux（GNU tar）和 docker。
#
# 用法: scripts/build-spk.sh <x86_64|armv8> <构建号>
#   例: scripts/build-spk.sh x86_64 1  生成 dist/syno-mihomo_x86_64_1.274.3-0001.spk
#
# spk 是不压缩的 tar，里面有：
#   INFO               套件信息（版本、架构、package.tgz 的 md5）
#   package.tgz        安装后解压到 target/：镜像 image.tar.gz、mihomo/（compose 和入口脚本）、ui/（DSM 主菜单图标）
#   scripts/           安装、卸载、启停脚本
#   conf/              privilege（以套件账号运行）、resource（docker-project）
#   PACKAGE_ICON*.PNG  套件中心图标
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${1:?用法: build-spk.sh <x86_64|armv8> <构建号>}"
BUILD_NUM="${2:?缺少构建号}"
case "$ARCH" in
    x86_64) PLATFORM=linux/amd64 ;;
    armv8) PLATFORM=linux/arm64 ;;
    *) echo "架构只能是 x86_64 或 armv8" >&2; exit 1 ;;
esac

UPSTREAM="$(tr -d '[:space:]' < UPSTREAM_VERSION)"
IMAGE="ghcr.io/metacubex/metacubexd-server:${UPSTREAM}"
VERSION="${UPSTREAM#v}-$(printf '%04d' "$BUILD_NUM")"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/package"

cp -R spk/package/mihomo spk/package/ui "$STAGE/package/"
sed -i "s|__UPSTREAM_VERSION__|${UPSTREAM}|" "$STAGE/package/mihomo/compose.yaml"

docker pull --platform "$PLATFORM" "$IMAGE"
actual="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$IMAGE")"
if [ "$actual" != "$PLATFORM" ]; then
    echo "镜像架构是 $actual，需要 $PLATFORM" >&2
    exit 1
fi
docker save "$IMAGE" | gzip -9 > "$STAGE/package/image.tar.gz"

TAR_OPTS=(--owner=0 --group=0 --numeric-owner --sort=name)
tar "${TAR_OPTS[@]}" -czf "$STAGE/package.tgz" -C "$STAGE/package" .
CHECKSUM="$(md5sum "$STAGE/package.tgz" | cut -d' ' -f1)"

sed -e "s|__VERSION__|${VERSION}|" -e "s|__ARCH__|${ARCH}|" -e "s|__CHECKSUM__|${CHECKSUM}|" \
    spk/INFO.tmpl | grep -v '^#' > "$STAGE/INFO"
cp -R spk/scripts spk/conf "$STAGE/"
chmod 0755 "$STAGE/scripts/"*
cp spk/PACKAGE_ICON.PNG spk/PACKAGE_ICON_256.PNG "$STAGE/"

mkdir -p dist
OUT="dist/syno-mihomo_${ARCH}_${VERSION}.spk"
tar "${TAR_OPTS[@]}" -cf "$OUT" -C "$STAGE" \
    INFO package.tgz scripts conf PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG
echo "$OUT"
