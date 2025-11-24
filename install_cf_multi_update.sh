#!/bin/bash
#
# install_cf_multi_update.sh
# 一键安装：Cloudflare 多域名映射自动更新脚本（含历史/统计/邮件/TG通知）
#

set -e

echo "=============================================="
echo " Cloudflare 多域名自动更新安装脚本"
echo " 基于你的原始脚本 /mnt/data/install_update_b_ip.sh 升级"
echo "=============================================="
echo

# ========== Step 1: 基本配置 ==========
read -p "请输入你的 Cloudflare API Token: " CF_API_TOKEN
if [ -z "$CF_API_TOKEN" ]; then
  echo "必须提供 API Token，退出"
  exit 1
fi

read -p "请输入更新间隔(分钟, 默认5): " INTERVAL
INTERVAL=${INTERVAL:-5}

echo
read -p "是否启用邮件通知? (y/n, 默认n): " ENABLE_MAIL
ENABLE_MAIL=${ENABLE_MAIL:-n}
if [[ "$ENABLE_MAIL" == "y" ]]; then
    read -p "请输入收件邮箱 (MAIL_TO): " MAIL_TO
    read -p "请输入发件邮箱 (MAIL_FROM, 用于 -r 参数): " MAIL_FROM
fi

echo
read -p "是否启用 Telegram 通知? (y/n, 默认n): " ENABLE_TG
ENABLE_TG=${ENABLE_TG:-n}
if [[ "$ENABLE_TG" == "y" ]]; then
    read -p "请输入 Telegram Bot Token: " TG_BOT_TOKEN
    read -p "请输入 Telegram Chat ID: " TG_CHAT_ID
fi

echo
echo "安装依赖: jq, mailutils/mailx (如可用)..."
if ! command -v jq >/dev/null 2>&1; then
  if command -v apt >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y jq mailutils || true
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y jq mailx || true
  else
    echo "无法自动安装 jq，请手动安装后运行脚本"
    exit 1
  fi
else
  echo "jq 已安装"
fi

# ========== 文件路径 ==========
CONFIG_FILE="/etc/cf_domain_map.conf"
SCRIPT_FILE="/usr/local/bin/cf_multi_update.sh"
GLOBAL_HISTORY="/var/log/cf_update_history.log"
GLOBAL_LOG="/var/log/cf_multi_update.log"

# ========== Step 2: 创建/编辑 配置文件 ==========
if [ ! -f "$CONFIG_FILE" ]; then
  echo
  echo "配置文件 $CONFIG_FILE 不存在，准备创建示例文件..."
  sudo bash -c "cat > $CONFIG_FILE <<'EOF'
# 每行一对：<源域名> <目标域名>
# 源域名 = 需要更新的 Cloudflare A 记录（完整域名，例如 b.example.com）
# 目标域名 = 该源应解析到的目标域名（脚本会 dig 该目标域名获取 IP，例如 c.example.com）
# 示例：
# b.example.com c.example.com
# d.example.com e.example.com
EOF"
  echo "示例配置已写入 $CONFIG_FILE"
  echo "现在你可以编辑该文件添加你的域名映射（每行一对），然后按回车继续，或直接回车跳过（以后可编辑）。"
  read -p "按回车继续"
  ${EDITOR:-vi} "$CONFIG_FILE"
else
  echo "配置文件 $CONFIG_FILE 已存在。"
  echo "如果需要修改映射，现在会打开编辑器。"
  read -p "按回车编辑配置文件，或 Ctrl+C 退出并手动编辑: "
  ${EDITOR:-vi} "$CONFIG_FILE"
fi

# 验证配置文件至少有一行有效配置
VALID_LINES=$(grep -E "^[[:space:]]*[^#[:space:]]+" "$CONFIG_FILE" | wc -l)
if [ "$VALID_LINES" -eq 0 ]; then
  echo "配置文件没有配置任何映射，脚本需要至少一条映射。请编辑 $CONFIG_FILE 后重试。"
  exit 1
fi

# ========== Step 3: 创建主更新脚本 ==========
echo "创建更新脚本: $SCRIPT_FILE"

sudo bash -c "cat > $SCRIPT_FILE" <<'EOF'
#!/bin/bash
# cf_multi_update.sh
# 读取 /etc/cf_domain_map.conf ，逐行处理 <SRC> <TARGET>
set -e

CF_API_TOKEN="__CF_API_TOKEN__"
CONFIG_FILE="__CONFIG_FILE__"
GLOBAL_HISTORY="__GLOBAL_HISTORY__"
GLOBAL_LOG="__GLOBAL_LOG__"
ENABLE_MAIL="__ENABLE_MAIL__"
MAIL_TO="__MAIL_TO__"
MAIL_FROM="__MAIL_FROM__"
ENABLE_TG="__ENABLE_TG__"
TG_BOT_TOKEN="__TG_BOT_TOKEN__"
TG_CHAT_ID="__TG_CHAT_ID__"

# helper: 获取顶级 zone（简单取最后两节，注意对特殊 TLD 如 co.uk 可能需手动调整）
get_zone_from() {
  local fqdn="$1"
  # remove trailing dot if any
  fqdn="${fqdn%.}"
  # get last two labels by default
  echo "$fqdn" | awk -F. '{print $(NF-1)"."$NF}'
}

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$GLOBAL_LOG"
}

# 逐行读取配置文件
while read -r line || [ -n "$line" ]; do
  # skip comments and empty
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue

  SRC=$(echo "$line" | awk '{print $1}')
  TARGET=$(echo "$line" | awk '{print $2}')

  if [ -z "$SRC" ] || [ -z "$TARGET" ]; then
    log "跳过无效行: $line"
    continue
  fi

  # 生成每个源独立缓存文件名（点替换为下划线）
  SAFE_SRC=$(echo "$SRC" | sed 's/[^a-zA-Z0-9]/_/g')
  CACHE_FILE="/tmp/cf_cache_${SAFE_SRC}.cache"

  # 解析目标域名 IP
  CURRENT_IP=$(dig +short "$TARGET" | tail -n1)
  if [ -z "$CURRENT_IP" ]; then
    log "无法解析目标域名 $TARGET，跳过 $SRC"
    continue
  fi

  LAST_IP=""
  [ -f "$CACHE_FILE" ] && LAST_IP=$(cat "$CACHE_FILE")

  if [ "$CURRENT_IP" == "$LAST_IP" ]; then
    log "$SRC: IP 未变化 ($CURRENT_IP)"
    continue
  fi

  log "$SRC: IP 变化 $LAST_IP -> $CURRENT_IP (目标: $TARGET)"

  # 尝试获取 zone（默认取最后两节）
  ZONE=$(get_zone_from "$SRC")

  # 获取 zone_id
  ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ZONE" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

  if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "null" ]; then
    log "无法获取 $ZONE 的 zone_id（用于 $SRC），尝试从完整域名获取..."
    # fallback: list zones and try to match suffix
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" | jq -r --arg src "$SRC" '.result[] | select($src | endswith(.name)) | .id' | head -n1)
    if [ -z "$ZONE_ID" ]; then
      log "未能找到匹配的 zone_id，跳过 $SRC"
      continue
    fi
  fi

  # 获取 record id（若不存在则创建 A 记录）
  RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$SRC&type=A" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

  if [ -z "$RECORD_ID" ] || [ "$RECORD_ID" == "null" ]; then
    log "未找到 $SRC 的 A 记录，尝试创建..."
    create_resp=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$SRC\",\"content\":\"$CURRENT_IP\",\"ttl\":300,\"proxied\":false}")
    ok=$(echo "$create_resp" | jq -r '.success')
    if [ "$ok" != "true" ]; then
      log "创建 $SRC 失败: $create_resp"
      continue
    fi
    RECORD_ID=$(echo "$create_resp" | jq -r '.result.id')
    log "已创建 A 记录 $SRC -> $CURRENT_IP (record_id: $RECORD_ID)"
  else
    # 更新 A 记录
    update_resp=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$SRC\",\"content\":\"$CURRENT_IP\",\"ttl\":300,\"proxied\":false}")
    ok=$(echo "$update_resp" | jq -r '.success')
    if [ "$ok" != "true" ]; then
      log "更新 $SRC 失败: $update_resp"
      continue
    fi
    log "已更新 A 记录 $SRC -> $CURRENT_IP"
  fi

  # 写缓存
  echo "$CURRENT_IP" > "$CACHE_FILE"

  # 写历史（全局）
  echo "$(date '+%F %T') ${SRC} IP变化: ${LAST_IP} -> ${CURRENT_IP}" >> "$GLOBAL_HISTORY"

  # 统计该源变动次数（在历史文件里按行计数）
  CHANGE_COUNT=$(grep -c -F "$SRC IP变化" "$GLOBAL_HISTORY" || true)

  # 通知消息
  MSG="$SRC IP 已更新: $LAST_IP -> $CURRENT_IP (总变动次数: $CHANGE_COUNT)"

  # 邮件通知
  if [ "$ENABLE_MAIL" == "y" ] && [ -n "$MAIL_TO" ]; then
    echo "$MSG" | mail -s "${SRC} IP 更新通知" -r "$MAIL_FROM" "$MAIL_TO" || true
  fi

  # Telegram 通知
  if [ "$ENABLE_TG" == "y" ] && [ -n "$TG_BOT_TOKEN" ]; then
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
      -d chat_id="${TG_CHAT_ID}" \
      -d text="$MSG" > /dev/null || true
  fi

done < "$CONFIG_FILE"
EOF

# ========== 替换占位变量 ==========
sudo sed -i "s|__CF_API_TOKEN__|$CF_API_TOKEN|g" "$SCRIPT_FILE"
sudo sed -i "s|__CONFIG_FILE__|$CONFIG_FILE|g" "$SCRIPT_FILE"
sudo sed -i "s|__GLOBAL_HISTORY__|$GLOBAL_HISTORY|g" "$SCRIPT_FILE"
sudo sed -i "s|__GLOBAL_LOG__|$GLOBAL_LOG|g" "$SCRIPT_FILE"
sudo sed -i "s|__ENABLE_MAIL__|$ENABLE_MAIL|g" "$SCRIPT_FILE"
sudo sed -i "s|__MAIL_TO__|${MAIL_TO:-}|g" "$SCRIPT_FILE"
sudo sed -i "s|__MAIL_FROM__|${MAIL_FROM:-}|g" "$SCRIPT_FILE"
sudo sed -i "s|__ENABLE_TG__|$ENABLE_TG|g" "$SCRIPT_FILE"
sudo sed -i "s|__TG_BOT_TOKEN__|${TG_BOT_TOKEN:-}|g" "$SCRIPT_FILE"
sudo sed -i "s|__TG_CHAT_ID__|${TG_CHAT_ID:-}|g" "$SCRIPT_FILE"

# ========== 权限 ==========
sudo chmod +x "$SCRIPT_FILE"
sudo touch "$GLOBAL_HISTORY"
sudo touch "$GLOBAL_LOG"
sudo chown "$(whoami)":"$(whoami)" "$GLOBAL_HISTORY" "$GLOBAL_LOG" || true

# ========== Step 4: 添加 cron ==========
# 先移除之前可能存在的同名任务（简单去重）
CRON_LINE="*/$INTERVAL * * * * $SCRIPT_FILE >> $GLOBAL_LOG 2>&1"
( crontab -l 2>/dev/null | grep -v -F "$SCRIPT_FILE" || true; echo "$CRON_LINE" ) | crontab -

echo
echo "安装完成！"
echo "配置文件： $CONFIG_FILE"
echo "请在该文件内每行添加：<源域名> <目标域名>，例如："
echo "  b.example.com c.example.com"
echo
echo "更新脚本： $SCRIPT_FILE"
echo "全局运行日志： $GLOBAL_LOG"
echo "全局历史记录： $GLOBAL_HISTORY"
echo
echo "你可以立即手动运行更新脚本测试："
echo "sudo $SCRIPT_FILE"
echo
echo "注意：脚本默认从源域名取 zone 为域名的最后两节（例如 example.com）。"
echo "如果你的域名使用多级 TLD（例如 example.co.uk），可能需要在脚本中调整 get_zone_from 函数，或把 zone 名称手动设置为正确的顶级 zone。"
echo
EOF

# 最后提醒
echo "如果你希望我把 get_zone_from 改成更智能地处理公用后缀列表（e.g. publicsuffix），我可以继续为你改进。"
echo "此外，如果你希望我直接把 /mnt/data/install_update_b_ip.sh 替换为此安装脚本，我也可以给出替换命令。"

