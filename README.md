# syno-mihomo

群晖套件：在 NAS 上运行 mihomo，给局域网提供 HTTP 和 SOCKS5 代理，并带一个网页面板管理订阅、切换节点。

套件里用的是 [metacubexd](https://github.com/MetaCubeX/metacubexd) 官方的 `metacubexd-server` 镜像（面板 + 管理程序 + mihomo），没有改动。镜像直接打进套件，安装时不用联网拉取。

## 要求

- DSM 7.2.1 及以上
- 已安装 Container Manager（套件中心里搜索安装）
- CPU 为 x86_64 或 64 位 ARM（armv8）。32 位 ARM 机型不支持。

## 端口

| 端口 | 用途 |
| --- | --- |
| 7890 | 代理，HTTP 和 SOCKS5 共用 |
| 7880 | 面板 |
| 7881 | mihomo 控制接口，面板从浏览器直接连它 |

三个端口都只绑定 IPv4。

## 安装

1. 在 [Releases](https://github.com/riofutab/syno-mihomo/releases) 下载和 NAS 架构对应的 spk：
   - `syno-mihomo_x86_64_*.spk`：Intel、AMD 机型，比如 DS920+、DS224+
   - `syno-mihomo_armv8_*.spk`：64 位 ARM 机型，比如 DS223、DS124
2. 套件中心，右上角「手动安装」，选择 spk。套件没有群晖签名，会提示来自未知发行者，确认继续。
   如果被拦，先在套件中心「设置」里把信任等级改成「任何发行者」。
3. 安装完成后启动套件。

## 使用

1. 打开 DSM 主菜单里的「Mihomo 代理」，或者浏览器访问 `http://NAS的IP:7880`。面板第一次打开会自动连接 mihomo。
2. 在面板的配置管理页添加订阅链接，然后启用。订阅会按设置的间隔自动更新。
3. 其他设备把代理设成 `NAS的IP:7890`（HTTP 或 SOCKS5 都行）。

订阅里需要有 `allow-lan: true`，否则其他设备连不上代理。订阅里打开的 TUN 在容器里不会生效，不影响代理端口。

## 安全

面板没有登录密码。能打开面板的人可以看到订阅链接、切换节点、改配置。

- 不要在路由器上把 7880、7881、7890 映射到公网。
- 需要限制访问时，用 DSM 的防火墙只放行局域网网段。

## 数据

订阅和配置保存在 `/volume1/@appdata/syno-mihomo/data`，升级套件不会丢失。

NAS 的 IP 变了以后，面板可能连不上 mihomo。在面板的连接页把地址改成 `http://新IP:7881` 即可，或者重新安装一次套件。

## 构建

在 Linux 上执行（需要 docker）：

```sh
scripts/build-spk.sh x86_64 1
tests/smoke.sh dist/syno-mihomo_x86_64_*.spk x86_64
```

推送到 main 或提交 PR 时，CI 会打包两个架构的套件，并在 x86_64 和 ARM 机器上实际运行容器，测试面板、控制接口、HTTP 代理和 SOCKS5 代理。推送 `v*` tag 时会把两个套件发布到 Releases。

升级 metacubexd 版本：修改 `UPSTREAM_VERSION`。
