#!/bin/bash

# ============================================
# FRP Panel Docker 入口脚本
# ============================================

set -e

FRP_DIR=${FRP_DIR:-/opt/frp}
FRP_MODE=${FRP_MODE:-server}  # server, client, or both

# 生成默认服务端配置
generate_frps_config() {
    if [ ! -f "$FRP_DIR/frps.toml" ]; then
        echo "生成默认服务端配置..."
        cat > "$FRP_DIR/frps.toml" << EOF
# FRP 服务端配置
bindPort = ${FRPS_BIND_PORT:-7000}

# Dashboard 配置
webServer.addr = "0.0.0.0"
webServer.port = ${FRPS_DASHBOARD_PORT:-7500}
webServer.user = "${FRPS_DASHBOARD_USER:-admin}"
webServer.password = "${FRPS_DASHBOARD_PWD:-admin123}"

# 认证配置
auth.method = "token"
auth.token = "${FRPS_TOKEN:-frp_panel_token}"

# 日志配置
log.to = "${FRP_DIR}/frps.log"
log.level = "info"
log.maxDays = 7
EOF
    fi
}

# 生成默认客户端配置
generate_frpc_config() {
    if [ ! -f "$FRP_DIR/frpc.toml" ]; then
        echo "生成默认客户端配置..."
        cat > "$FRP_DIR/frpc.toml" << EOF
# FRP 客户端配置
serverAddr = "${FRPC_SERVER_ADDR:-127.0.0.1}"
serverPort = ${FRPC_SERVER_PORT:-7000}

# 认证配置
auth.method = "token"
auth.token = "${FRPC_TOKEN:-frp_panel_token}"

# 日志配置
log.to = "${FRP_DIR}/frpc.log"
log.level = "info"
log.maxDays = 7

# 代理配置
[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000
EOF
    fi
}

# 启动 FRP 服务端
start_frps() {
    echo "启动 FRP 服务端..."
    $FRP_DIR/frps -c $FRP_DIR/frps.toml &
    FRPS_PID=$!
    echo "FRP 服务端已启动 (PID: $FRPS_PID)"
}

# 启动 FRP 客户端
start_frpc() {
    echo "启动 FRP 客户端..."
    $FRP_DIR/frpc -c $FRP_DIR/frpc.toml &
    FRPC_PID=$!
    echo "FRP 客户端已启动 (PID: $FRPC_PID)"
}

# 启动 Web 面板
start_panel() {
    echo "启动 Web 管理面板..."
    cd /app
    python -m uvicorn main:app --host 0.0.0.0 --port 8000 &
    PANEL_PID=$!
    echo "Web 管理面板已启动 (PID: $PANEL_PID)"
}

# 信号处理
cleanup() {
    echo "正在停止服务..."
    [ -n "$FRPS_PID" ] && kill $FRPS_PID 2>/dev/null
    [ -n "$FRPC_PID" ] && kill $FRPC_PID 2>/dev/null
    [ -n "$PANEL_PID" ] && kill $PANEL_PID 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT

# 主逻辑
echo "============================================"
echo "  FRP Panel Docker Container"
echo "  Mode: $FRP_MODE"
echo "============================================"

case $FRP_MODE in
    server)
        generate_frps_config
        start_frps
        ;;
    client)
        generate_frpc_config
        start_frpc
        ;;
    both)
        generate_frps_config
        generate_frpc_config
        start_frps
        sleep 2
        start_frpc
        ;;
    panel-only)
        # 仅启动面板，用于外部 FRP 实例
        ;;
    *)
        echo "未知模式: $FRP_MODE"
        echo "支持的模式: server, client, both, panel-only"
        exit 1
        ;;
esac

# 启动 Web 面板
start_panel

echo ""
echo "============================================"
echo "  所有服务已启动"
echo "  Web 面板: http://localhost:8000"
echo "  API 文档: http://localhost:8000/api/docs"
echo "============================================"

# 保持容器运行
wait
