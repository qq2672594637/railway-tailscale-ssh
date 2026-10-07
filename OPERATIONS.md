# Railway + Tailscale 容器接管操作手册

> 适用于本项目：`https://github.com/qq2672594637/railway-tailscale-ssh`
>
> 目标：在 Railway 部署一个只运行 Tailscale + OpenSSH 的容器。容器自动加入指定 tailnet，并通过 Tailscale 内网地址的 `2222` 端口 SSH 进入容器。整个过程不需要 Railway 公网域名或 TCP Proxy。

## 一、最终架构

```text
本机 SSH 客户端
    │
    │ Tailscale 网络：<容器 Tailscale IP>:2222
    ▼
Railway 容器
    ├── tailscaled（userspace 模式）
    ├── Tailscale Serve：2222 → 127.0.0.1:22
    └── OpenSSH：127.0.0.1:22

Railway Volume：/data
    ├── /data/tailscale   Tailscale 节点身份
    └── /data/ssh         SSH 主机密钥
```

`TS_USERSPACE=true` 是为了适配 Railway 通常没有 `/dev/net/tun` 的容器环境。OpenSSH 只监听容器本机，外部访问通过 Tailscale Serve 的 tailnet-only TCP 转发进入。

## 二、开始前的安全处理

### 1. 撤销旧的 Tailscale 密钥

如果密钥曾经发到聊天、工单、截图或公开仓库，应在 Tailscale 管理控制台撤销它，并检查 Machines 列表中是否有陌生设备。

不要把以下内容提交到 GitHub：

- `TS_AUTHKEY`
- SSH 私钥，例如 `id_ed25519`
- Railway API Token
- 任何密码

### 2. 创建新的 Tailscale 认证密钥

在 Tailscale 管理控制台创建新的预授权密钥：

- 建议关闭 **Ephemeral**；
- 建议设置短期有效期；
- 如果使用设备审批，提前允许设备加入；
- 仅把密钥填入 Railway 的 Secret Variable。

不要把真实密钥写入本手册。

## 三、准备本机 SSH 密钥

在 Windows PowerShell 执行：

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519"
```

如果已有这对密钥，不要覆盖，直接查看公钥：

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

复制输出的**完整一行**，格式类似：

```text
ssh-ed25519 AAAAC3... 你的电脑
```

这个值用于 Railway 变量：

```text
SSH_AUTHORIZED_KEY=<上面整行公钥>
```

注意：

- `id_ed25519.pub` 是公钥，可以填入 Railway；
- `id_ed25519` 是私钥，只保留在本机，不能上传；
- `SSH_AUTHORIZED_KEY` 不是 Tailscale 的 `TS_AUTHKEY`。

## 四、部署 GitHub 项目到 Railway

### 方案 A：直接使用本项目

1. 打开 Railway。
2. 创建项目，选择 **GitHub Repository**。
3. 选择：

   ```text
   qq2672594637/railway-tailscale-ssh
   ```

4. Railway 检测根目录中的 `Dockerfile` 并构建镜像。

不要选择单独的 `tailscale/tailscale:stable` Docker Image，因为本项目需要在镜像构建阶段安装 OpenSSH，并安装入口脚本。

### 方案 B：复制到新的 GitHub 账号

如果换了 GitHub 账号：

1. Fork 本项目，或复制以下文件到新仓库根目录：
   - `Dockerfile`
   - `entrypoint.sh`
   - `sshd_config`
   - `README.md`
2. 在 Railway 导入新账号下的 GitHub 仓库。
3. 确保 `Dockerfile` 位于仓库根目录。

## 五、Railway 配置

### 1. 创建持久 Volume

在 Railway 项目画布中：

1. 回到项目画布；
2. 右键 Tailscale 服务，选择 **Create Volume / Add Volume**；
3. 挂载路径填写：

```text
/data
```

这是稳定连接的关键。没有 Volume 时，`/data` 会落在临时 `overlay` 文件系统中，重启后节点身份和 SSH 主机密钥可能丢失。

### 2. 添加 Service Variables

在服务的 **Variables → New Variable** 中添加：

| 变量名 | 值 | 说明 |
|---|---|---|
| `TS_AUTHKEY` | 新生成的 Tailscale 预授权密钥 | 设为 Secret，不要提交仓库 |
| `TS_STATE_DIR` | `/data/tailscale` | 必须与 Volume 配合 |
| `TS_AUTH_ONCE` | `true` | 已有状态时不重复注册 |
| `TS_USERSPACE` | `true` | 不依赖 TUN 设备 |
| `TS_HOSTNAME` | `railway-tail-node` | Tailscale 设备名称 |
| `SSH_AUTHORIZED_KEY` | 本机 `.pub` 文件完整内容 | 只填公钥 |

不要手动修改 Railway 自动添加的 `RAILWAY_*` 变量。

不要添加或保留旧的：

```text
TS_EXTRA_ARGS=--ssh
TS_SERVE_CONFIG=...
```

本项目使用的是普通 OpenSSH + Tailscale Serve，不使用 Tailscale SSH。

### 3. 部署

1. 保存变量和 Volume；
2. 打开 **Deployments**；
3. 执行 **Deploy / Redeploy**；
4. 等待构建和启动完成。

不要创建：

- Railway Public Domain；
- Railway TCP Proxy；
- 公开的 22 端口。

## 六、验证部署是否成功

### 1. 查看 Railway 日志

日志中应能看到类似：

```text
Server listening on 127.0.0.1 port 22.
Tailscale SSH bridge ready
```

如果看到 Tailscale 进入 `Running`，表示节点已登录。

### 2. 在 Railway Console 检查 Volume

执行：

```sh
df -hT /data
```

正确结果应类似：

```text
/dev/zdXXXX  ext4  ...  /data
```

如果显示：

```text
overlay ... /
```

说明没有正确挂载 Volume，需要回到 Railway 项目画布重新绑定 `/data`。

### 3. 检查 Tailscale Serve

在 Railway Console 执行：

```sh
tailscale serve status
```

正确结果应类似：

```text
|-- tcp://railway-tail-node.<tailnet>.ts.net:2222 (tailnet only)
|-- tcp://100.x.y.z:2222
|--> tcp://127.0.0.1:22
```

### 4. 检查 SSH 监听

```sh
ss -lntp
```

应看到：

```text
127.0.0.1:22
```

## 七、从本机连接容器

先在 Tailscale Machines 页面查看当前设备 IP。假设当前 IP 是 `100.71.64.71`，执行：

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519" -p 2222 root@100.71.64.71
```

第一次连接会询问 SSH 主机指纹，确认后输入 `yes`。

如果启用了 MagicDNS，也可以使用设备名：

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519" -p 2222 root@railway-tail-node
```

连接成功后检查：

```sh
id
hostname
uname -a
tailscale status
tailscale serve status
```

## 八、换新 Tailscale 账号或新 tailnet

1. 在新账号的 Tailscale 管理控制台创建新的预授权密钥；
2. 新密钥必须替换 Railway 的 `TS_AUTHKEY`；
3. 如果希望新账号获得新的设备身份，删除旧 Railway Volume 后再部署；
4. 如果希望保留原设备身份，不要删除 Volume，但要确认新账号有权接管对应设备；
5. Railway 重新部署；
6. 在新 tailnet 的 Machines 页面查找 `railway-tail-node`；
7. 用新页面显示的 Tailscale IP 连接。

通常“换新账号/新 tailnet”建议使用新 Volume，避免旧 tailnet 的状态文件残留。

## 九、常见问题

### 问题 1：`Connection timed out`

依次检查：

```powershell
tailscale status
tailscale ping <当前Tailscale-IP>
```

- `tailscale ping` 失败：节点离线、IP 已变化或 Tailscale 状态异常；
- `tailscale ping` 成功但 SSH 超时：检查 `tailscale serve status` 是否仍有 `2222 → 127.0.0.1:22`。

### 问题 2：`Host key verification failed`

如果确认这是自己的 Railway 节点，可以删除旧指纹：

```powershell
ssh-keygen -R "[<Tailscale-IP>]:2222"
```

然后重新连接。

### 问题 3：`Permission denied (publickey)`

确认 Railway 的 `SSH_AUTHORIZED_KEY` 与本机私钥匹配：

```powershell
ssh-keygen -y -f "$env:USERPROFILE\.ssh\id_ed25519"
```

输出应与 Railway 中的公钥对应。不要把私钥发给任何人。

### 问题 4：Tailscale IP 变化

检查：

- `/data` 是否真的挂载为独立 Volume；
- `TS_STATE_DIR` 是否是 `/data/tailscale`；
- Tailscale 密钥是否勾选了 Ephemeral；
- 是否删除过 Railway Volume；
- 是否创建了新的设备而不是恢复旧设备。

### 问题 5：日志提示 Serve CLI 参数错误

确认 Railway 正在构建 GitHub 仓库最新 `main` 分支，而不是旧镜像或旧部署。当前入口脚本中的关键命令是：

```sh
tailscale serve --bg --tcp "$TAILSCALE_SSH_PORT" "tcp://127.0.0.1:${SSH_PORT}"
```

重新部署后应看到 `Tailscale SSH bridge ready`。

## 十、最终检查清单

- [ ] 使用新且未泄露的 `TS_AUTHKEY`
- [ ] Tailscale 密钥未勾选 Ephemeral
- [ ] Railway Volume 已挂载到 `/data`
- [ ] `TS_STATE_DIR=/data/tailscale`
- [ ] `TS_USERSPACE=true`
- [ ] `TS_AUTH_ONCE=true`
- [ ] `SSH_AUTHORIZED_KEY` 是本机 `.pub` 公钥
- [ ] 没有把私钥提交到 GitHub
- [ ] 没有创建 Railway 公网 TCP Proxy
- [ ] `tailscale serve status` 显示 `2222 → 127.0.0.1:22`
- [ ] `ssh -p 2222` 可以连接
- [ ] Tailscale Machines 中设备不是陌生节点
