#!/bin/bash

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 设置环境变量
DIR=/ql
DIR_LOG=/ql/log

# 创建日志目录
mkdir -p "$DIR_LOG"

# 0. 验证持久化存储
log "======================0. 验证持久化存储========================"
if ! touch /ql/data/test_write || ! rm /ql/data/test_write; then
    log "错误：/ql/data 不可写，请检查是否正确挂载持久化存储"
    exit 1
fi
log "持久化存储验证通过"

# 1. 初始化数据库
log "======================1. 初始化数据库========================"
if [ -f /ql/data/db/database.sqlite ]; then
    sqlite3 /ql/data/db/database.sqlite "PRAGMA integrity_check;" || {
        log "错误：数据库文件已损坏，将尝试备份并创建新数据库"
        cp /ql/data/db/database.sqlite /ql/data/db/database.sqlite.corrupted
        rm /ql/data/db/database.sqlite
    }
fi
sqlite3 /ql/data/db/database.sqlite "PRAGMA journal_mode=WAL;"
log "数据库初始化完成，WAL 模式已启用"

# 2. 启动青龙服务（假设使用 pm2 管理）
log "======================2. 启动青龙服务========================"
pm2 start /ql/scripts/app.js --name qinglong || {
    log "错误：青龙服务启动失败"
    exit 1
}
log "青龙服务已启动"

# 3. 延迟启动数据同步服务
log "======================3. 启动数据同步服务========================"
sleep 10  # 等待青龙服务稳定
nohup /sync_data.sh >"$DIR_LOG/sync.log" 2>&1 &
log "数据同步服务已启动，日志输出至 $DIR_LOG/sync.log"

# 保持容器运行
log "容器启动完成，进入等待状态..."
pm2 logs
