FROM python:3.10-slim

# 安装依赖
RUN apt update && apt install -y \
    curl bash nginx tar \
    && pip install huggingface_hub \
    && apt clean && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /ql

# 拷贝脚本
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY sync_data.sh /sync_data.sh

# 如果有 shell 脚本目录
COPY shell /ql/shell

# 给予执行权限
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /sync_data.sh

# 替换默认 nginx 配置（如有）
# COPY nginx.conf /etc/nginx/nginx.conf

# 设置环境变量（可在 Koyeb 控制台 override）
ENV AutoStartBot=true \
    EnableExtraShell=false \
    ADMIN_USERNAME=admin \
    ADMIN_PASSWORD=123456 \
    SYNC_INTERVAL=7200

# 启动脚本
ENTRYPOINT ["docker-entrypoint.sh"]
