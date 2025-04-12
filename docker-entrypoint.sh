#!/bin/bash

# 定义常量
DIR_SHELL=/ql/shell
DIR_LOG=/ql/data/log

# 加载共享脚本
source "$DIR_SHELL/share.sh"
source "$DIR_SHELL/env.sh"

# 日志函数
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "======================1. 检测配置文件========================"
import_config "$@"
make_dir /etc/nginx/conf.d
make_dir /run/nginx
init_nginx
fix_config

# 检查 pm2 是否可用
pm2 l &>/dev/null || log "警告：pm2 未正确安装或配置"

log "======================2. 安装依赖========================"
patch_version

log "======================3. 启动 Nginx========================"
if ! nginx -s reload 2>/dev/null; then
  nginx -c /etc/nginx/nginx.conf && log "Nginx 启动成功" || { log "Nginx 启动失败"; exit 1; }
else
  log "Nginx 重载成功"
fi

log "======================4. 启动 PM2 服务========================"
reload_update
reload_pm2

if [[ "$AutoStartBot" == true ]]; then
  log "======================5. 启动 Bot========================"
  nohup ql bot >"$DIR_LOG/bot.log" 2>&1 &
  log "Bot 已后台启动，日志输出至 $DIR_LOG/bot.log"
fi

if [[ "$EnableExtraShell" == true ]]; then
  log "======================6. 执行自定义脚本========================"
  nohup ql extra >"$DIR_LOG/extra.log" 2>&1 &
  log "自定义脚本已后台执行，日志输出至 $DIR_LOG/extra.log"
fi

log "======================7. 启动数据同步服务========================"
/sync_data.sh &

log "############################################################"
log "容器启动成功"
log "############################################################"

log "########## 写入登录信息 ############"
echo "{ \"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\" }" > /ql/data/config/auth.json

# 保持容器运行
exec tail -f /dev/null

# 执行传入的命令（如果有）
exec "$@"