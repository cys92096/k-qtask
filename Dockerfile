# 使用官方 Ubuntu 22.04 作为基础镜像
FROM ubuntu:22.04

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm \
    TZ=Asia/Shanghai \
    DIR=/ql

# 设置工作目录
WORKDIR $DIR

# 创建用户和目录结构
RUN useradd -m -s /bin/bash user && \
    mkdir -p /ql/data/{config,log,db,scripts,repo,raw,deps} && \
    chown -R user:user /ql

# 更新系统并安装必要的工具
RUN set -ex && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install --no-install-recommends -y \
        git curl cron wget tzdata perl openssl openssh-client nginx jq \
        procps netcat-traditional sshpass unzip libatomic1 python3-venv \
        python3-pip sqlite3 pm2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 设置权限
RUN chmod -R 755 /ql && \
    chmod -R 775 /ql/data /ql/log /ql/db

# 复制入口脚本和同步脚本
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY sync_data.sh /sync_data.sh

# 设置脚本权限
RUN chmod +x /docker-entrypoint.sh /sync_data.sh

# 暴露端口
EXPOSE 5700

# 设置入口点
ENTRYPOINT ["/docker-entrypoint.sh"]

# 健康检查：验证服务可用性和数据库完整性
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -sf --noproxy '*' http://127.0.0.1:5700/api/health && \
        sqlite3 /ql/data/db/database.sqlite "PRAGMA quick_check;" || exit 1
