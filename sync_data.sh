#!/bin/bash

# 检查环境变量
if [[ -z "$HF_TOKEN" ]] || [[ -z "$DATASET_ID" ]]; then
    echo "Starting without backup functionality - missing HF_TOKEN or DATASET_ID"
    exit 0
fi

# 激活虚拟环境
source /opt/venv/bin/activate

# 上传备份
upload_backup() {
    file_path="$1"
    file_name="$2"
    token="$HF_TOKEN"
    repo_id="$DATASET_ID"

    python3 -c "
from huggingface_hub import HfApi
import sys
import os
api = HfApi(token='$token')
try:
    api.upload_file(
        path_or_fileobj='$file_path',
        path_in_repo='$file_name',
        repo_id='$repo_id',
        repo_type='dataset'
    )
    print(f'Successfully uploaded $file_name')
except Exception as e:
    print(f'Error uploading file: {str(e)}')
"
}

# 下载最新备份
download_latest_backup() {
    token="$HF_TOKEN"
    repo_id="$DATASET_ID"

    python3 -c "
from huggingface_hub import HfApi
import sys
import os
import tarfile
import tempfile
api = HfApi(token='$token')
try:
    files = api.list_repo_files(repo_id='$repo_id', repo_type='dataset')
    backup_files = [f for f in files if f.startswith('qinglong_backup_') and f.endswith('.tar.gz')]
    
    if not backup_files:
        print('No backup files found')
        sys.exit()
        
    latest_backup = sorted(backup_files)[-1]
    
    with tempfile.TemporaryDirectory() as temp_dir:
        filepath = api.hf_hub_download(
            repo_id='$repo_id',
            filename=latest_backup,
            repo_type='dataset',
            local_dir=temp_dir
        )
        
        if filepath and os.path.exists(filepath):
            with tarfile.open(filepath, 'r:gz') as tar:
                tar.extractall('/ql/data')
            print(f'Successfully restored backup from {latest_backup}')
        
except Exception as e:
    print(f'Error downloading backup: {str(e)}')
"
}

# 首次启动时下载最新备份
echo "Downloading latest backup from HuggingFace..."
download_latest_backup

# 同步函数
sync_data() {
    while true; do
        echo "Starting sync process at $(date)"
        
        if [ -d /ql/data ]; then
            timestamp=$(date +%Y%m%d_%H%M%S)
            backup_file="qinglong_backup_${timestamp}.tar.gz"
            
            # 压缩数据目录
            tar -czf "/tmp/${backup_file}" -C /ql/data .
            
            echo "Uploading backup to HuggingFace..."
            upload_backup "/tmp/${backup_file}" "${backup_file}"
            
            rm -f "/tmp/${backup_file}"
        else
            echo "Data directory does not exist yet, waiting for next sync..."
        fi
        
        SYNC_INTERVAL=${SYNC_INTERVAL:-7200}
        echo "Next sync in ${SYNC_INTERVAL} seconds..."
        sleep $SYNC_INTERVAL
    done
}

# 启动同步进程
sync_data
