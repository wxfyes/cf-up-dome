# 使用步骤（简短）

## 此脚本是自动检测域名IP，发生变化则通过CF进行自动A记录解析，实现自动更换IP功能！

赋执行权限并运行（推荐 sudo）：
```
wget https://raw.githubusercontent.com/wxfyes/cf-up-dome/refs/heads/main/install_cf_multi_update.sh && chmod +x install_cf_multi_update.sh && ./install_cf_multi_update.sh
```
2.按提示输入：

Cloudflare API Token

3.顶级域名（如 xxx.com）

b.xxx.com

c.xxx.com

4.更新间隔

5.是否启用邮件通知 + 邮箱信息

6.是否启用 Telegram 通知 + Bot Token + Chat ID

每次 IP 更新，会自动更新 DNS、邮件/TG通知，并记录历史与变动次数

这样你就拥有了一个 全自动、带历史和通知的 b.xxx.com IP 更新系统 ✅
按提示填写 Cloudflare API Token、是否启用邮件/TG、并在编辑器中维护 /etc/cf_domain_map.conf（每行一对 <源> <目标>）。

安装完成后，crontab 会每 INTERVAL 分钟运行 /usr/local/bin/cf_multi_update.sh。

查看日志：/var/log/cf_multi_update.log，历史记录保存在 /var/log/cf_update_history.log。
# 一键卸载脚本执行命令
```
wget https://raw.githubusercontent.com/wxfyes/cf-up-dome/refs/heads/main/uninstall_cf_update.sh && chmod +x uninstall_cf_update.sh && ./uninstall_cf_update.sh
```
# 获取CF令牌
1️⃣ 登录 Cloudflare

打开 Cloudflare 登录页面

使用你的账户登录

2️⃣ 进入“我的个人资料”

点击右上角头像 → My Profile（我的个人资料）

在左侧菜单找到 API Tokens（API 令牌）

3️⃣ 创建 API Token

点击 Create Token（创建令牌）

Cloudflare 提供模板，你可以选择 Edit DNS 模板

这个模板允许你修改指定域名的 DNS 记录，非常适合你的需求

修改权限：

Zone → DNS → Edit（必须）

Zone → Zone → Read（可选，便于获取 zone ID）

指定域名：

可以设置为 Include → Specific Zone → 填写你的域名（如 xxx.com）

点击 Continue to summary → Create Token

4️⃣ 保存 API Token

创建成功后，会显示一个长字符串，这就是你的 API Token

注意：这是唯一一次可以看到完整令牌，请务必复制并妥善保存

这个令牌就是脚本中要求填写的 CF_API_TOKEN
