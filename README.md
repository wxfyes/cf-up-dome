# 使用步骤（简短）

## 此脚本是自动检测域名IP，发生变化则通过CF进行自动A记录解析，实现自动更换IP功能！

赋执行权限并运行（推荐 sudo）：
```
wget https://raw.githubusercontent.com/wxfyes/cf-up-dome/refs/heads/main/install_cf_multi_update.sh && chmod +x install_cf_multi_update.sh && ./install_cf_multi_update.sh
```

按提示填写 Cloudflare API Token、是否启用邮件/TG、并在编辑器中维护 /etc/cf_domain_map.conf（每行一对 <源> <目标>）。

安装完成后，crontab 会每 INTERVAL 分钟运行 /usr/local/bin/cf_multi_update.sh。

查看日志：/var/log/cf_multi_update.log，历史记录保存在 /var/log/cf_update_history.log。
# 一键卸载脚本执行命令
```
wget https://raw.githubusercontent.com/wxfyes/cf-up-dome/refs/heads/main/uninstall_cf_update.sh && chmod +x uninstall_cf_update.sh && ./uninstall_cf_update.sh
```

