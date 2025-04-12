# Stage 1: Node.js 构建阶段
FROM node:20-slim AS nodebuilder

# Stage 2: 依赖构建阶段
FROM python:3.11-slim-bullseye AS builder
ARG QL_MAINTAINER="whyour"
LABEL maintainer="${QL_MAINTAINER}"
ARG QL_URL="https://github.com/${QL_MAINTAINER}/qinglong.git"
ARG QL_BRANCH="debian"

ENV QT_DIR="/qtast" \
    QL_BRANCH="${QL_BRANCH}"

# 复制 Node.js 相关文件
COPY --from=nodebuilder /usr/local/bin/node /usr/local/bin/
COPY --from=nodebuilder /usr/local/lib/node_modules/. /usr/local/lib/node_modules/

# 安装构建依赖并克隆代码
RUN set -ex && \
    ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    apt-get update && \
    apt-get install --no-install-recommends -y git libatomic1 && \
    git config --global user.email "qtast@users.noreply.github.com" && \
    git config --global user.name "qtast" && \
    git config --global http.postBuffer 524288000 && \
    git clone --depth=1 -b "${QL_BRANCH}" "${QL_URL}" "${QT_DIR}" && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 准备 Node.js 依赖
WORKDIR /tmp/build
RUN cp "${QT_DIR}/package.json" "${QT_DIR}/.npmrc" . && \
    if [ -f "${QT_DIR}/pnpm-lock.yaml" ]; then cp "${QT_DIR}/pnpm-lock.yaml" .; fi
RUN npm install -g pnpm@8.3.1 && \
    pnpm install --prod && \
    rm -rf /root/.npm /root/.cache

# Stage 3: 最终镜像
FROM python:3.11-slim-bullseye
ARG QL_MAINTAINER="whyour"
LABEL maintainer="${QL_MAINTAINER}"
ARG QL_URL="https://github.com/${QL_MAINTAINER}/qinglong.git"
ARG QL_BRANCH="debian"

# 环境变量
ENV PNPM_HOME="/root/.local/share/pnpm" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/.local/share/pnpm:/root/.local/share/pnpm/global/5/node_modules:/opt/venv/bin:$PATH" \
    NODE_PATH="/usr/local/bin:/usr/local/pnpm-global/5/node_modules:/usr/local/lib/node_modules:/root/.local/share/pnpm/global/5/node_modules" \
    LANG="C.UTF-8" \
    SHELL="/bin/bash" \
    PS1="\u@\h:\w \$ " \
    QT_DIR="/qtast" \
    QL_BRANCH="${QL_BRANCH}" \
    VIRTUAL_ENV="/opt/venv"

# 复制 Node.js 文件
COPY --from=nodebuilder /usr/local/bin/node /usr/local/bin/
COPY --from=nodebuilder /usr/local/lib/node_modules/. /usr/local/lib/node_modules/

# 安装运行时依赖并配置
RUN set -ex && \
    ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install --no-install-recommends -y \
        git curl cron wget tzdata perl openssl openssh-client nginx jq procps netcat-traditional sshpass unzip libatomic1 python3-venv python3-pip sqlite3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    git config --global user.email "qtast@users.noreply.github.com" && \
    git config --global user.name "qtast" && \
    git config --global http.postBuffer 524288000 && \
    npm install -g pnpm@8.3.1 ts-node && \
    python3 -m venv "${VIRTUAL_ENV}" && \
    . "${VIRTUAL_ENV}/bin/activate" && \
    pip install --no-cache-dir huggingface_hub requests && \
    rm -rf /root/.pnpm-store /root/.local/share/pnpm/store /root/.cache /root/.npm && \
    chmod u+s /usr/sbin/cron && \
    ulimit -c 0

# 克隆代码并构建
ARG SOURCE_COMMIT
RUN set -ex && \
    git clone --depth=1 -b "${QL_BRANCH}" "${QL_URL}" "${QT_DIR}" && \
    cd "${QT_DIR}" && \
    pnpm install && \
    npm run build:back && \
    npm run build:front && \
    cp -f .env.example .env && \
    chmod 777 "${QT_DIR}"/shell/*.sh "${QT_DIR}"/docker/*.sh && \
    git clone --depth=1 -b "${QL_BRANCH}" "https://github.com/${QL_MAINTAINER}/qinglong-static.git" /static && \
    mkdir -p "${QT_DIR}/static" && \
    cp -rf /static/* "${QT_DIR}/static" && \
    rm -rf /static "${QT_DIR}/docker/docker-entrypoint.sh"

# 复制脚本
COPY docker-entrypoint.sh "${QT_DIR}/docker/"
COPY sync_data.sh /
RUN chmod +x /sync_data.sh

# 创建数据目录并设置权限
RUN mkdir -p /qtast/data/{config,log,db,scripts,repo,raw,deps} && \
    chmod -R 777 /qtast /var /usr/local /etc/nginx /run /usr /root

# 复制 Node.js 依赖
COPY --from=builder /tmp/build/node_modules/. /qtast/node_modules/

WORKDIR "${QT_DIR}"

# 创建用户并切换
RUN useradd -m -u 1000 user
USER user

# 健康检查
HEALTHCHECK --interval=5s --timeout=2s --retries=20 \
    CMD curl -sf --noproxy '*' http://127.0.0.1:7860/api/health || exit 1

# 入口点和暴露端口
ENTRYPOINT ["./docker/docker-entrypoint.sh"]
EXPOSE 7860
