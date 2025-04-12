#!/bin/bash

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 下载最新备份（示例函数，需替换为实际逻辑）
download_latest_backup() {
    log "从 Hugging Face 下载最新备份（示例）..."
    # 示例：wget -O /ql/data/db/database.sqlite "https://example.com/backup.sqlite"
}

# 上传备份（示例函数，需替换为实际逻辑）
upload_backup() {
    local temp_file="$1"
    local backup_file="$2"
    log "上传备份 $backup_file 到 Hugging Face（示例）..."
    # 示例：curl -F "file=@$temp_file" https://example.com/upload
}

# 备份数据库
backup_database() {
    local timestamp="$1"
    local temp_db="/tmp/database_${timestamp}.sqlite"
    sqlite3 /ql/data/db/database.sqlite ".backup '$temp_db'" || {
        log "错误：备份数据库失败"
        return 1
    }
    echo "$temp_db"
}

# 暂停青龙服务
pause_services() {
    pm2 stop all && log "已暂停青龙服务" || log "警告：暂停服务失败"
}

# 恢复青龙服务
resume_services() {
    pm2 start all && log "已恢复青龙服务" || log "警告：恢复服务失败"
}

# 首次启动检查
if [[ ! -f /ql/data/db/database.sqlite ]]; then
    log "数据库文件缺失，从 Hugging Face 下载最新备份..."
    download_latest_backup
else
    log "数据库文件存在，跳过初始备份下载"
fi

# 数据同步函数
sync_data() {
    while true; do
        log "开始同步进程"
        if [[ -d /ql/data ]]; then
            local timestamp=$(date +%Y%m%d_%H%M%S)
            local backup_file="qinglong_backup_${timestamp}.tar.gz"
            local temp_file="/tmp/${backup_file}"

            pause_services
            local temp_db
            temp_db=$(backup_database "$timestamp") || {
                resume_services
                sleep 60
                continue
            }
            tar -czf "$temp_file" -C /ql/data . && log "数据目录压缩成功" || {
                log "错误：压缩数据目录失败"
                rm -f "$temp_db"
                resume_services
                sleep 60
                continue
            }
            resume_services
            log "正在上传备份到 Hugging Face..."
            upload_backup "$temp_file" "$backup_file"
            rm -f "$temp_file" "$temp_db" && log "临时文件已清理" || log "警告：清理临时文件失败"
        else
            log "数据目录 /ql/data 不存在，等待下次同步..."
        fi
        SYNC_INTERVAL=${SYNC_INTERVAL:-7200}  # 默认同步间隔 2 小时
        log "下次同步将在 ${SYNC_INTERVAL} 秒后执行..."
        sleep "$SYNC_INTERVAL"
    done
}

# 启动同步
sync_data
