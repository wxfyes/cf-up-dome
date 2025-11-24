# 使用步骤（简短）

将上面脚本保存为 install_cf_multi_update.sh（或你喜欢的名字）。

赋执行权限并运行（推荐 sudo）：

chmod +x install_cf_multi_update.sh
sudo ./install_cf_multi_update.sh


按提示填写 Cloudflare API Token、是否启用邮件/TG、并在编辑器中维护 /etc/cf_domain_map.conf（每行一对 <源> <目标>）。

安装完成后，crontab 会每 INTERVAL 分钟运行 /usr/local/bin/cf_multi_update.sh。

查看日志：/var/log/cf_multi_update.log，历史记录保存在 /var/log/cf_update_history.log。
# 一键卸载脚本执行命令
chmod +x uninstall_cf_update.sh
sudo ./uninstall_cf_update.sh

