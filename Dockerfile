# 阶段1：Node.js构建阶段，用于安装pnpm和前端依赖
FROM node:20-slim AS nodebuilder

RUN npm install -g pnpm@8.3.1 && \
    mkdir -p /tmp/build && \
    pnpm config set store-dir /tmp/.pnpm-store

# 阶段2：构建青龙前端依赖
FROM python:3.11-slim-bullseye AS builder
ARG QL_MAINTAINER="whyour"
LABEL maintainer="${QL_MAINTAINER}"
ARG QL_URL=https://github.com/${QL_MAINTAINER}/qinglong.git
ARG QL_BRANCH=debian

ENV QL_DIR=/ql

COPY --from=nodebuilder /usr/local/bin/node /usr/local/bin/
COPY --from=nodebuilder /usr/local/lib/node_modules /usr/local/lib/node_modules/
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    npm install -g pnpm@8.3.1

WORKDIR /tmp/build
COPY package.json .npmrc pnpm-lock.yaml ./
RUN pnpm install --prod && \
    rm -rf /root/.pnpm-store /root/.cache

# 阶段3：最终运行时镜像
FROM python:3.11-slim-bullseye

ARG QL_MAINTAINER="whyour"
LABEL maintainer="${QL_MAINTAINER}"
ARG QL_URL=https://github.com/${QL_MAINTAINER}/qinglong.git
ARG QL_BRANCH=debian

ENV PNPM_HOME=/root/.local/share/pnpm \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/.local/share/pnpm:/opt/venv/bin \
    NODE_PATH=/usr/local/lib/node_modules:/root/.local/share/pnpm/global/5/node_modules \
    LANG=C.UTF-8 \
    SHELL=/bin/bash \
    PS1="\u@\h:\w \$ " \
    QL_DIR=/ql \
    VIRTUAL_ENV=/opt/venv

COPY --from=nodebuilder /usr/local/bin/node /usr/local/bin/
COPY --from=nodebuilder /usr/local/lib/node_modules /usr/local/lib/node_modules/

RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        curl \
        cron \
        wget \
        tzdata \
        perl \
        openssl \
        openssh-client \
        nginx \
        jq \
        procps \
        netcat-openbsd \
        sshpass \
        unzip \
        libatomic1 \
        python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    git config --global user.email "qinglong@users.noreply.github.com" && \
    git config --global user.name "qinglong" && \
    git config --global http.postBuffer 524288000 && \
    npm install -g pnpm@8.3.1 pm2 ts-node && \
    python3 -m venv $VIRTUAL_ENV && \
    . $VIRTUAL_ENV/bin/activate && \
    pip install --no-cache-dir huggingface_hub requests && \
    rm -rf /root/.cache /root/.npm

WORKDIR ${QL_DIR}

ARG SOURCE_COMMIT
RUN git clone --depth=1 -b ${QL_BRANCH} ${QL_URL} ${QL_DIR} && \
    cp -f .env.example .env && \
    git clone --depth=1 -b ${QL_BRANCH} https://github.com/${QL_MAINTAINER}/qinglong-static.git /static && \
    mkdir -p ${QL_DIR}/static && \
    cp -rf /static/* ${QL_DIR}/static && \
    rm -rf /static

COPY --from=builder /tmp/build/node_modules ./node_modules/
COPY docker-entrypoint.sh ./docker/
COPY sync_data.sh /
RUN chmod +x /sync_data.sh ./docker/docker-entrypoint.sh && \
    mkdir -p /ql/data/{config,log,db,scripts,repo,raw,deps} && \
    chown -R 1000:1000 /ql /ql/data && \
    chmod -R 755 /ql /ql/data && \
    chmod u+s /usr/sbin/cron

USER 1000
HEALTHCHECK --interval=5s --timeout=2s --retries=20 \
    CMD curl -sf --noproxy '*' http://127.0.0.1:5400/api/health || exit 1

VOLUME /ql/data
EXPOSE 5700

ENTRYPOINT ["./docker/docker-entrypoint.sh"]
