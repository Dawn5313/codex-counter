# ccodexr 更新 feed 与 rollout 约定

## 当前状态

- 当前仓库已经接入**单一版本事实源**：`release-feed/stable.json`
- 客户端运行时只读取这一份 feed，不再把 GitHub Releases 当成版本真相
- 当前稳定策略是 **guidedDownload**
- 这意味着当前版本只支持：
  - 启动自动检查
  - 手动检查更新
  - 发现新版后提示
  - 根据架构打开匹配安装包下载
- 当前版本**不宣称**已经具备自动替换旧 app 并自动重启的闭环

## 为什么当前仍是 guidedDownload

Phase 0 gate 的本地证据表明当前还不满足成熟 macOS updater 的前置条件：

- `/Applications/ccodexr.app` 当前是 `adhoc` 签名，`spctl` 显示 `source=no usable signature`
- 仓库里还没有成熟 updater 引擎接入
- 仓库里还没有正式 feed 签名/发布流水线
- Bootstrap / Rollout Gate 仍要求：`1.1.5 -> 首个支持 updater 的版本` 必须人工安装进入

因此当前产品策略必须诚实降级，不能伪装成已经完成全自动更新。

## Feed 字段

`release-feed/stable.json` 当前约定：

- `schemaVersion`: feed schema 版本
- `channel`: 当前渠道，默认 `stable`
- `release.version`: 客户端比较的新版本号
- `release.releaseNotesURL`: 版本说明链接
- `release.downloadPageURL`: 人工下载页
- `release.deliveryMode`:
  - `guidedDownload`
  - `automatic`
- `release.minimumAutomaticUpdateVersion`: 自动更新闭环起点版本
- `release.artifacts[]`: 架构 + 格式 + 下载地址 + 校验摘要

资产映射约定：

- Apple Silicon 优先匹配 `arm64`，其次 `universal`
- Intel 优先匹配 `x86_64`，其次 `universal`
- 格式优先级：`dmg` 高于 `zip`

## 发布顺序

单一 feed 生效时，必须遵守顺序：

1. 先准备可安装资产
2. 再准备 `release-feed/stable.json`
3. 最后发布/更新 feed

这样客户端不会先看见一个“存在但不可安装”的版本。

## 生成 feed

可直接编辑 `release-feed/stable.json`，也可以使用脚本做规范化输出：

```sh
python3 scripts/generate_update_feed.py release-feed/stable.json release-feed/stable.json
```

如果某个 artifact 额外提供了 `localPath`，脚本会在本地文件存在时自动计算 `sha256` 并写回输出。

## Phase 0 gate 检查

在把 `deliveryMode` 从 `guidedDownload` 切到 `automatic` 之前，先运行：

```sh
scripts/check_update_readiness.sh /Applications/ccodexr.app
scripts/check_update_readiness.sh "$HOME/Applications/ccodexr.app"
scripts/check_update_readiness.sh "/private/tmp/ccodexr-phase0/ccodexr.app"
```

至少要核对：

- `/Applications`
- `~/Applications`
- 非标准路径
- 签名 / 公证 / 权限 / 重启时序
- `mdfind` / `lsregister` 不留下多个 `ccodexr.app`

## 切到 automatic 的前置条件

只有以下条件同时满足，才允许把 feed 切到 `automatic`：

1. 已接入成熟 updater 引擎
2. 当前发布产物具备可信签名与对应发布前提
3. feed / metadata 生成与发布顺序固定
4. Bootstrap / Rollout Gate 已跑通：
   - 首个支持 updater 的版本通过人工安装进入
   - 再用下一版本验证真正自动更新闭环
5. `/Applications`、`~/Applications`、非标准路径的支持边界已经明确

## 回滚

如果某个版本需要撤回，不要只删 GitHub Release 资产。应优先回滚 `release-feed/stable.json` 到上一个可安装版本，让客户端立刻停止提示被撤回的版本。
