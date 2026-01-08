# ============================================
# FRP Panel Dockerfile
# 多阶段构建，包含 FRP + Web 管理面板
# ============================================

FROM python:3.11-slim as builder

# 安装构建依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 下载 FRP
ARG FRP_VERSION=0.61.1
ARG TARGETARCH
RUN ARCH=$(echo ${TARGETARCH} | sed 's/amd64/amd64/;s/arm64/arm64/;s/arm\/v7/arm/') && \
    wget -q https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz && \
    tar -xzf frp_${FRP_VERSION}_linux_${ARCH}.tar.gz && \
    mv frp_${FRP_VERSION}_linux_${ARCH} /frp

# ============================================
# 最终镜像
# ============================================
FROM python:3.11-slim

LABEL maintainer="ychenfen"
LABEL description="FRP Panel - 内网穿透管理面板"
LABEL version="1.0.0"

# 安装运行时依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
    && rm -rf /var/lib/apt/lists/*

# 创建工作目录
WORKDIR /app

# 复制 FRP 二进制文件
COPY --from=builder /frp/frps /opt/frp/frps
COPY --from=builder /frp/frpc /opt/frp/frpc
RUN chmod +x /opt/frp/frps /opt/frp/frpc

# 复制后端代码
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/main.py .

# 复制前端文件
COPY frontend/index.html /app/static/index.html

# 创建配置目录
RUN mkdir -p /opt/frp

# 环境变量
ENV FRP_DIR=/opt/frp
ENV PYTHONUNBUFFERED=1

# 暴露端口
# 7000: FRP 服务端口
# 7500: FRP Dashboard
# 8000: Web 管理面板
EXPOSE 7000 7500 8000

# 启动脚本
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
