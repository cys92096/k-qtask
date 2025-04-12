#!/bin/bash

# 日志函数
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 检查环境变量
if [[ -z "$HF_TOKEN" ]] || [[ -z "$DATASET_ID" ]]; then
  log "错误：缺少 HF_TOKEN 或 DATASET_ID，备份功能不可用"
  exit 0
fi

# 激活虚拟环境
source /opt/venv/bin/activate || { log "错误：无法激活虚拟环境"; exit 1; }

# 上传备份函数
upload_backup() {
  local file_path="$1"
  local file_name="$2"
  local token="$HF_TOKEN"
  local repo_id="$DATASET_ID"

  python3 -c "
from huggingface_hub import HfApi
import sys
api = HfApi(token='$token')
try:
    api.upload_file(
        path_or_fileobj='$file_path',
        path_in_repo='$file_name',
        repo_id='$repo_id',
        repo_type='dataset'
    )
    print('Successfully uploaded $file_name')
except Exception as e:
    print(f'Error uploading file: {str(e)}')
    sys.exit(1)
" || log "警告：上传备份 $file_name 失败"
}

# 下载最新备份函数
download_latest_backup() {
  local token="$HF_TOKEN"
  local repo_id="$DATASET_ID"

  python3 -c "
from huggingface_hub import HfApi, hf_hub_download
import sys, os, tarfile, tempfile, sqlite3
api = HfApi(token='$token')
try:
    files = api.list_repo_files(repo_id='$repo_id', repo_type='dataset')
    backup_files = [f for f in files if f.startswith('qtast_backup_') and f.endswith('.tar.gz')]
    if not backup_files:
        print('No backup files found')
        sys.exit(0)
    for backup in sorted(backup_files, reverse=True):
        with tempfile.TemporaryDirectory() as temp_dir:
            filepath = hf_hub_download(
                repo_id='$repo_id',
                filename=backup,
                repo_type='dataset',
                local_dir=temp_dir
            )
            if os.path.exists(filepath):
                with tarfile.open(filepath, 'r:gz') as tar:
                    tar.extractall('/tmp/check_db')
                db_path = '/tmp/check_db/db/database.sqlite'
                if os.path.exists(db_path):
                    conn = sqlite3.connect(db_path)
                    cursor = conn.cursor()
                    cursor.execute('PRAGMA integrity_check;')
                    result = cursor.fetchone()[0]
                    conn.close()
                    if result == 'ok':
                        with tarfile.open(filepath, 'r:gz') as tar:
                            tar.extractall('/qtast/data')
                        print(f'Successfully restored backup from {backup}')
                        sys.exit(0)
                    else:
                        print(f'Backup {backup} contains corrupted database, trying next...')
                else:
                    with tarfile.open(filepath, 'r:gz') as tar:
                        tar.extractall('/qtast/data')
                    print(f'Successfully restored backup from {backup}')
                    sys.exit(0)
    print('No valid backup found')
except Exception as e:
    print(f'Error downloading backup: {str(e)}')
    sys.exit(1)
" || log "警告：下载最新备份失败"
}

# 首次启动时下载最新备份
log "开始从 Hugging Face 下载最新备份..."
download_latest_backup

# 数据同步函数
sync_data() {
  while true; do
    log "开始同步进程"
    
    if [[ -d /qtast/data ]]; then
      local timestamp=$(date +%Y%m%d_%H%M%S)
      local backup_file="qtast_backup_${timestamp}.tar.gz"
      local temp_file="/tmp/${backup_file}"

      tar -czf "$temp_file" -C /qtast/data . && log "数据目录压缩成功" || {
        log "错误：压缩数据目录失败"
        sleep 60
        continue
      }

      log "正在上传备份到 Hugging Face..."
      upload_backup "$temp_file" "$backup_file"

      rm -f "$temp_file" && log "临时文件已清理" || log "警告：清理临时文件失败"
    else
      log "数据目录 /qtast/data 不存在，等待下次同步..."
    fi

    SYNC_INTERVAL=${SYNC_INTERVAL:-7200}
    log "下次同步将在 ${SYNC_INTERVAL} 秒后执行..."
    sleep "$SYNC_INTERVAL"
  done
}

# 启动同步进程
sync_data
