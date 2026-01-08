#!/bin/bash

# ============================================
# FRP 一键部署脚本
# 项目地址: https://github.com/ychenfen/frp-panel
# 作者: ychenfen
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# FRP 版本
FRP_VERSION="0.61.1"
INSTALL_DIR="/opt/frp"
SERVICE_NAME=""

# 打印 Banner
print_banner() {
    echo -e "${CYAN}"
    echo "  _____ ____  ____    ____                  _ "
    echo " |  ___|  _ \|  _ \  |  _ \ __ _ _ __   ___| |"
    echo " | |_  | |_) | |_) | | |_) / _\` | '_ \ / _ \ |"
    echo " |  _| |  _ <|  __/  |  __/ (_| | | | |  __/ |"
    echo " |_|   |_| \_\_|     |_|   \__,_|_| |_|\___|_|"
    echo -e "${NC}"
    echo -e "${GREEN}FRP 一键部署脚本 v1.0${NC}"
    echo -e "${YELLOW}项目地址: https://github.com/ychenfen/frp-panel${NC}"
    echo ""
}

# 打印信息
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "arm"
            ;;
        i386|i686)
            echo "386"
            ;;
        *)
            error "不支持的系统架构: $arch"
            ;;
    esac
}

# 检测操作系统
detect_os() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case $os in
        linux)
            echo "linux"
            ;;
        darwin)
            echo "darwin"
            ;;
        freebsd)
            echo "freebsd"
            ;;
        *)
            error "不支持的操作系统: $os"
            ;;
    esac
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请使用 root 权限运行此脚本 (sudo $0)"
    fi
}

# 安装依赖
install_dependencies() {
    info "检查并安装依赖..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq wget curl tar
    elif command -v yum &> /dev/null; then
        yum install -y -q wget curl tar
    elif command -v dnf &> /dev/null; then
        dnf install -y -q wget curl tar
    else
        warn "无法自动安装依赖，请确保已安装 wget, curl, tar"
    fi
}

# 下载 FRP
download_frp() {
    local os=$(detect_os)
    local arch=$(detect_arch)
    local filename="frp_${FRP_VERSION}_${os}_${arch}.tar.gz"
    local url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${filename}"
    
    info "检测到系统: ${os}/${arch}"
    info "正在下载 FRP v${FRP_VERSION}..."
    
    # 创建临时目录
    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir"
    
    # 下载
    if command -v wget &> /dev/null; then
        wget -q --show-progress "$url" -O "$filename" || error "下载失败"
    elif command -v curl &> /dev/null; then
        curl -L --progress-bar "$url" -o "$filename" || error "下载失败"
    else
        error "请安装 wget 或 curl"
    fi
    
    # 解压
    info "正在解压..."
    tar -xzf "$filename"
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 复制文件
    local extract_dir="frp_${FRP_VERSION}_${os}_${arch}"
    cp "$extract_dir/frps" "$INSTALL_DIR/"
    cp "$extract_dir/frpc" "$INSTALL_DIR/"
    
    # 清理
    cd /
    rm -rf "$tmp_dir"
    
    info "FRP 已安装到 $INSTALL_DIR"
}

# 生成服务端配置
generate_frps_config() {
    local bind_port=${1:-7000}
    local dashboard_port=${2:-7500}
    local dashboard_user=${3:-admin}
    local dashboard_pwd=${4:-admin123}
    local token=${5:-$(openssl rand -hex 16)}
    
    cat > "$INSTALL_DIR/frps.toml" << EOF
# FRP 服务端配置
# 由 FRP-Panel 自动生成

bindPort = ${bind_port}

# Dashboard 配置
webServer.addr = "0.0.0.0"
webServer.port = ${dashboard_port}
webServer.user = "${dashboard_user}"
webServer.password = "${dashboard_pwd}"

# 认证配置
auth.method = "token"
auth.token = "${token}"

# 日志配置
log.to = "${INSTALL_DIR}/frps.log"
log.level = "info"
log.maxDays = 7
EOF

    info "服务端配置已生成: $INSTALL_DIR/frps.toml"
    echo ""
    echo -e "${PURPLE}========== 重要信息 ==========${NC}"
    echo -e "绑定端口: ${GREEN}${bind_port}${NC}"
    echo -e "Dashboard: ${GREEN}http://YOUR_SERVER_IP:${dashboard_port}${NC}"
    echo -e "Dashboard 用户名: ${GREEN}${dashboard_user}${NC}"
    echo -e "Dashboard 密码: ${GREEN}${dashboard_pwd}${NC}"
    echo -e "认证 Token: ${GREEN}${token}${NC}"
    echo -e "${PURPLE}==============================${NC}"
    echo ""
    warn "请妥善保存以上信息，客户端连接时需要使用 Token"
}

# 生成客户端配置
generate_frpc_config() {
    local server_addr=${1:-"YOUR_SERVER_IP"}
    local server_port=${2:-7000}
    local token=${3:-"YOUR_TOKEN"}
    
    cat > "$INSTALL_DIR/frpc.toml" << EOF
# FRP 客户端配置
# 由 FRP-Panel 自动生成

serverAddr = "${server_addr}"
serverPort = ${server_port}

# 认证配置
auth.method = "token"
auth.token = "${token}"

# 日志配置
log.to = "${INSTALL_DIR}/frpc.log"
log.level = "info"
log.maxDays = 7

# 代理配置示例 - SSH
[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000

# 代理配置示例 - Web
# [[proxies]]
# name = "web"
# type = "http"
# localIP = "127.0.0.1"
# localPort = 80
# customDomains = ["www.example.com"]
EOF

    info "客户端配置已生成: $INSTALL_DIR/frpc.toml"
    echo ""
    echo -e "${PURPLE}========== 配置说明 ==========${NC}"
    echo -e "服务器地址: ${GREEN}${server_addr}${NC}"
    echo -e "服务器端口: ${GREEN}${server_port}${NC}"
    echo -e "默认代理: SSH (本地22端口 -> 远程6000端口)"
    echo -e "${PURPLE}==============================${NC}"
    echo ""
    warn "请根据实际需求修改配置文件: $INSTALL_DIR/frpc.toml"
}

# 创建 systemd 服务
create_systemd_service() {
    local service_type=$1  # frps 或 frpc
    local service_file="/etc/systemd/system/${service_type}.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=FRP ${service_type} Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${service_type} -c ${INSTALL_DIR}/${service_type}.toml
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${service_type}"
    
    info "Systemd 服务已创建: ${service_type}"
    echo ""
    echo -e "启动服务: ${GREEN}sudo systemctl start ${service_type}${NC}"
    echo -e "停止服务: ${GREEN}sudo systemctl stop ${service_type}${NC}"
    echo -e "查看状态: ${GREEN}sudo systemctl status ${service_type}${NC}"
    echo -e "查看日志: ${GREEN}sudo journalctl -u ${service_type} -f${NC}"
}

# 交互式安装服务端
install_server() {
    echo ""
    echo -e "${CYAN}========== 安装 FRP 服务端 ==========${NC}"
    echo ""
    
    # 获取配置
    read -p "绑定端口 [默认: 7000]: " bind_port
    bind_port=${bind_port:-7000}
    
    read -p "Dashboard 端口 [默认: 7500]: " dashboard_port
    dashboard_port=${dashboard_port:-7500}
    
    read -p "Dashboard 用户名 [默认: admin]: " dashboard_user
    dashboard_user=${dashboard_user:-admin}
    
    read -p "Dashboard 密码 [默认: admin123]: " dashboard_pwd
    dashboard_pwd=${dashboard_pwd:-admin123}
    
    read -p "认证 Token [留空自动生成]: " token
    
    # 下载并安装
    download_frp
    
    # 生成配置
    generate_frps_config "$bind_port" "$dashboard_port" "$dashboard_user" "$dashboard_pwd" "$token"
    
    # 创建服务
    create_systemd_service "frps"
    
    echo ""
    read -p "是否立即启动服务? [Y/n]: " start_now
    if [[ "$start_now" != "n" && "$start_now" != "N" ]]; then
        systemctl start frps
        info "FRP 服务端已启动!"
        systemctl status frps --no-pager
    fi
}

# 交互式安装客户端
install_client() {
    echo ""
    echo -e "${CYAN}========== 安装 FRP 客户端 ==========${NC}"
    echo ""
    
    # 获取配置
    read -p "服务器地址: " server_addr
    if [ -z "$server_addr" ]; then
        error "服务器地址不能为空"
    fi
    
    read -p "服务器端口 [默认: 7000]: " server_port
    server_port=${server_port:-7000}
    
    read -p "认证 Token: " token
    if [ -z "$token" ]; then
        error "认证 Token 不能为空"
    fi
    
    # 下载并安装
    download_frp
    
    # 生成配置
    generate_frpc_config "$server_addr" "$server_port" "$token"
    
    # 创建服务
    create_systemd_service "frpc"
    
    echo ""
    read -p "是否立即启动服务? [Y/n]: " start_now
    if [[ "$start_now" != "n" && "$start_now" != "N" ]]; then
        systemctl start frpc
        info "FRP 客户端已启动!"
        systemctl status frpc --no-pager
    fi
}

# 卸载 FRP
uninstall_frp() {
    echo ""
    echo -e "${YELLOW}========== 卸载 FRP ==========${NC}"
    echo ""
    
    read -p "确定要卸载 FRP 吗? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        info "已取消卸载"
        exit 0
    fi
    
    # 停止并禁用服务
    systemctl stop frps 2>/dev/null || true
    systemctl stop frpc 2>/dev/null || true
    systemctl disable frps 2>/dev/null || true
    systemctl disable frpc 2>/dev/null || true
    
    # 删除服务文件
    rm -f /etc/systemd/system/frps.service
    rm -f /etc/systemd/system/frpc.service
    systemctl daemon-reload
    
    # 删除安装目录
    rm -rf "$INSTALL_DIR"
    
    info "FRP 已完全卸载"
}

# 显示菜单
show_menu() {
    echo ""
    echo -e "${CYAN}请选择要执行的操作:${NC}"
    echo ""
    echo "  1) 安装 FRP 服务端 (frps)"
    echo "  2) 安装 FRP 客户端 (frpc)"
    echo "  3) 卸载 FRP"
    echo "  4) 退出"
    echo ""
    read -p "请输入选项 [1-4]: " choice
    
    case $choice in
        1)
            install_server
            ;;
        2)
            install_client
            ;;
        3)
            uninstall_frp
            ;;
        4)
            info "再见!"
            exit 0
            ;;
        *)
            error "无效选项"
            ;;
    esac
}

# 主函数
main() {
    print_banner
    check_root
    install_dependencies
    show_menu
}

# 运行
main "$@"
