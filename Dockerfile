# 使用官方 Python 镜像
FROM python:3.10-slim

# 设置时区和基本工具
ENV TZ=Asia/Shanghai
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash curl nginx tar gnupg \
        && rm -rf /var/lib/apt/lists/*

# 创建必要目录
RUN mkdir -p /ql/data /ql/shell /opt/venv /run/nginx /etc/nginx/conf.d

# 设置 Python 虚拟环境
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir huggingface_hub

# 拷贝脚本文件
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY sync_data.sh /sync_data.sh

# 赋予执行权限
RUN chmod +x /docker-entrypoint.sh /sync_data.sh

# Nginx 默认配置（如有自定义配置可另行 COPY）
RUN echo 'daemon off;' >> /etc/nginx/nginx.conf

# 设置必要环境变量（可通过外部覆盖）
ENV SYNC_INTERVAL=7200
ENV HF_TOKEN=""
ENV DATASET_ID=""
ENV ADMIN_USERNAME=admin
ENV ADMIN_PASSWORD=123456
ENV AutoStartBot=true
ENV EnableExtraShell=false

# 端口暴露（nginx 默认端口）
EXPOSE 80

# 默认启动脚本
ENTRYPOINT ["/docker-entrypoint.sh"]
