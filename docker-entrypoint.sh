#!/bin/bash

# 定义常量
DIR_SHELL=/qtast/shell
DIR_LOG=/qtast/data/log
DATA_DIR=/qtast/data

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
sed -i 's/listen 5700/listen 7860/g' /etc/nginx/conf.d/front.conf
init_nginx
fix_config

log "======================2. 安装依赖========================"
patch_version

log "======================3. 启动 Nginx========================"
if ! nginx -s reload 2>/dev/null; then
  nginx -c /etc/nginx/nginx.conf && log "Nginx 启动成功" || { log "Nginx 启动失败"; exit 1; }
else
  log "Nginx 重载成功"
fi

log "======================4. 检查和修复数据库========================"
DB_PATH="$DATA_DIR/db/database.sqlite"
if [ -f "$DB_PATH" ]; then
  sqlite3 "$DB_PATH" "PRAGMA integrity_check;" > /tmp/db_check.log 2>&1
  if grep -q "database disk image is malformed" /tmp/db_check.log; then
    log "数据库损坏，删除并重建..."
    rm -f "$DB_PATH"
  fi
fi

log "======================5. 启动 qtast 服务========================"
cd /qtast
npm run build:back
node static/build/app.js &
node static/build/schedule/index.js &
node static/build/public.js &
node static/build/update.js &

log "======================6. 启动数据同步服务========================"
/sync_data.sh &

log "############################################################"
log "容器启动成功"
log "############################################################"

log "########## 写入登录信息 ############"
echo "{ \"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\" }" > "$DATA_DIR/config/auth.json"

# 保持容器运行
tail -f /dev/null
