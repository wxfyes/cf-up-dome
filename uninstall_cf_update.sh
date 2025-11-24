echo "停止并删除 cron 任务..."
crontab -l 2>/dev/null | grep -v "cf_multi_update.sh" | crontab -

echo "删除主脚本..."
sudo rm -f /usr/local/bin/cf_multi_update.sh

echo "删除配置文件..."
sudo rm -f /etc/cf_domain_map.conf

echo "删除日志和历史记录..."
sudo rm -f /var/log/cf_multi_update.log
sudo rm -f /var/log/cf_update_history.log

echo "删除缓存文件..."
sudo rm -f /tmp/cf_cache_*

echo "清理完成！Cloudflare 自动更新系统已完全卸载。"
