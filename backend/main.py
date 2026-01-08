"""
FRP Panel - Web 管理面板后端
基于 FastAPI 开发的轻量级 FRP 配置管理 API
"""

import os
import json
import subprocess
import tomli
import tomli_w
from pathlib import Path
from typing import Optional, List
from datetime import datetime

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

# ============================================
# 配置
# ============================================

FRP_DIR = os.environ.get("FRP_DIR", "/opt/frp")
FRPS_CONFIG = os.path.join(FRP_DIR, "frps.toml")
FRPC_CONFIG = os.path.join(FRP_DIR, "frpc.toml")
FRPS_LOG = os.path.join(FRP_DIR, "frps.log")
FRPC_LOG = os.path.join(FRP_DIR, "frpc.log")

# ============================================
# Pydantic 模型
# ============================================

class ProxyBase(BaseModel):
    """代理基础模型"""
    name: str = Field(..., description="代理名称")
    type: str = Field(..., description="代理类型: tcp, udp, http, https, stcp, xtcp")
    local_ip: str = Field(default="127.0.0.1", alias="localIP", description="本地 IP")
    local_port: int = Field(..., alias="localPort", description="本地端口")

class TCPProxy(ProxyBase):
    """TCP 代理"""
    type: str = "tcp"
    remote_port: int = Field(..., alias="remotePort", description="远程端口")

class UDPProxy(ProxyBase):
    """UDP 代理"""
    type: str = "udp"
    remote_port: int = Field(..., alias="remotePort", description="远程端口")

class HTTPProxy(ProxyBase):
    """HTTP 代理"""
    type: str = "http"
    custom_domains: List[str] = Field(default=[], alias="customDomains", description="自定义域名")
    subdomain: Optional[str] = Field(default=None, description="子域名")

class HTTPSProxy(ProxyBase):
    """HTTPS 代理"""
    type: str = "https"
    custom_domains: List[str] = Field(default=[], alias="customDomains", description="自定义域名")
    subdomain: Optional[str] = Field(default=None, description="子域名")

class ProxyCreate(BaseModel):
    """创建代理请求"""
    name: str
    type: str = "tcp"
    local_ip: str = "127.0.0.1"
    local_port: int
    remote_port: Optional[int] = None
    custom_domains: Optional[List[str]] = None
    subdomain: Optional[str] = None

class ProxyResponse(BaseModel):
    """代理响应"""
    name: str
    type: str
    local_ip: str
    local_port: int
    remote_port: Optional[int] = None
    custom_domains: Optional[List[str]] = None
    subdomain: Optional[str] = None

class ServerConfig(BaseModel):
    """服务端配置"""
    bind_port: int = Field(default=7000, alias="bindPort")
    dashboard_port: Optional[int] = Field(default=7500, alias="dashboardPort")
    dashboard_user: Optional[str] = Field(default="admin", alias="dashboardUser")
    dashboard_pwd: Optional[str] = Field(default=None, alias="dashboardPwd")
    token: Optional[str] = None

class ClientConfig(BaseModel):
    """客户端配置"""
    server_addr: str = Field(..., alias="serverAddr")
    server_port: int = Field(default=7000, alias="serverPort")
    token: Optional[str] = None

class ServiceStatus(BaseModel):
    """服务状态"""
    name: str
    running: bool
    pid: Optional[int] = None
    uptime: Optional[str] = None

class LogResponse(BaseModel):
    """日志响应"""
    logs: List[str]
    total_lines: int

# ============================================
# FastAPI 应用
# ============================================

app = FastAPI(
    title="FRP Panel API",
    description="FRP 内网穿透管理面板 API",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
)

# CORS 配置
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================
# 工具函数
# ============================================

def read_toml_config(config_path: str) -> dict:
    """读取 TOML 配置文件"""
    if not os.path.exists(config_path):
        return {}
    with open(config_path, "rb") as f:
        return tomli.load(f)

def write_toml_config(config_path: str, config: dict):
    """写入 TOML 配置文件"""
    with open(config_path, "wb") as f:
        tomli_w.dump(config, f)

def get_service_status(service_name: str) -> ServiceStatus:
    """获取 systemd 服务状态"""
    try:
        result = subprocess.run(
            ["systemctl", "is-active", service_name],
            capture_output=True,
            text=True
        )
        running = result.stdout.strip() == "active"
        
        pid = None
        uptime = None
        if running:
            # 获取 PID
            pid_result = subprocess.run(
                ["systemctl", "show", service_name, "--property=MainPID"],
                capture_output=True,
                text=True
            )
            pid_line = pid_result.stdout.strip()
            if "=" in pid_line:
                pid = int(pid_line.split("=")[1])
            
            # 获取运行时间
            uptime_result = subprocess.run(
                ["systemctl", "show", service_name, "--property=ActiveEnterTimestamp"],
                capture_output=True,
                text=True
            )
            uptime_line = uptime_result.stdout.strip()
            if "=" in uptime_line:
                uptime = uptime_line.split("=")[1]
        
        return ServiceStatus(name=service_name, running=running, pid=pid, uptime=uptime)
    except Exception:
        return ServiceStatus(name=service_name, running=False)

def restart_service(service_name: str) -> bool:
    """重启 systemd 服务"""
    try:
        subprocess.run(["systemctl", "restart", service_name], check=True)
        return True
    except subprocess.CalledProcessError:
        return False

def read_log_file(log_path: str, lines: int = 100) -> LogResponse:
    """读取日志文件最后 N 行"""
    if not os.path.exists(log_path):
        return LogResponse(logs=[], total_lines=0)
    
    try:
        result = subprocess.run(
            ["tail", "-n", str(lines), log_path],
            capture_output=True,
            text=True
        )
        log_lines = result.stdout.strip().split("\n") if result.stdout.strip() else []
        
        # 获取总行数
        wc_result = subprocess.run(
            ["wc", "-l", log_path],
            capture_output=True,
            text=True
        )
        total = int(wc_result.stdout.split()[0]) if wc_result.stdout else 0
        
        return LogResponse(logs=log_lines, total_lines=total)
    except Exception:
        return LogResponse(logs=[], total_lines=0)

# ============================================
# API 路由 - 系统状态
# ============================================

@app.get("/api/status", tags=["系统"])
async def get_system_status():
    """获取系统状态"""
    frps_status = get_service_status("frps")
    frpc_status = get_service_status("frpc")
    
    return {
        "frps": frps_status.dict(),
        "frpc": frpc_status.dict(),
        "frp_dir": FRP_DIR,
        "frps_config_exists": os.path.exists(FRPS_CONFIG),
        "frpc_config_exists": os.path.exists(FRPC_CONFIG),
    }

@app.post("/api/service/{service_name}/restart", tags=["系统"])
async def restart_frp_service(service_name: str):
    """重启 FRP 服务"""
    if service_name not in ["frps", "frpc"]:
        raise HTTPException(status_code=400, detail="无效的服务名称")
    
    success = restart_service(service_name)
    if not success:
        raise HTTPException(status_code=500, detail=f"重启 {service_name} 失败")
    
    return {"message": f"{service_name} 已重启", "success": True}

@app.post("/api/service/{service_name}/start", tags=["系统"])
async def start_frp_service(service_name: str):
    """启动 FRP 服务"""
    if service_name not in ["frps", "frpc"]:
        raise HTTPException(status_code=400, detail="无效的服务名称")
    
    try:
        subprocess.run(["systemctl", "start", service_name], check=True)
        return {"message": f"{service_name} 已启动", "success": True}
    except subprocess.CalledProcessError:
        raise HTTPException(status_code=500, detail=f"启动 {service_name} 失败")

@app.post("/api/service/{service_name}/stop", tags=["系统"])
async def stop_frp_service(service_name: str):
    """停止 FRP 服务"""
    if service_name not in ["frps", "frpc"]:
        raise HTTPException(status_code=400, detail="无效的服务名称")
    
    try:
        subprocess.run(["systemctl", "stop", service_name], check=True)
        return {"message": f"{service_name} 已停止", "success": True}
    except subprocess.CalledProcessError:
        raise HTTPException(status_code=500, detail=f"停止 {service_name} 失败")

# ============================================
# API 路由 - 服务端配置
# ============================================

@app.get("/api/server/config", tags=["服务端"])
async def get_server_config():
    """获取服务端配置"""
    config = read_toml_config(FRPS_CONFIG)
    return config

@app.put("/api/server/config", tags=["服务端"])
async def update_server_config(config: ServerConfig):
    """更新服务端配置"""
    current_config = read_toml_config(FRPS_CONFIG)
    
    # 更新配置
    current_config["bindPort"] = config.bind_port
    
    if config.dashboard_port:
        if "webServer" not in current_config:
            current_config["webServer"] = {}
        current_config["webServer"]["port"] = config.dashboard_port
        current_config["webServer"]["addr"] = "0.0.0.0"
        
        if config.dashboard_user:
            current_config["webServer"]["user"] = config.dashboard_user
        if config.dashboard_pwd:
            current_config["webServer"]["password"] = config.dashboard_pwd
    
    if config.token:
        if "auth" not in current_config:
            current_config["auth"] = {}
        current_config["auth"]["method"] = "token"
        current_config["auth"]["token"] = config.token
    
    write_toml_config(FRPS_CONFIG, current_config)
    
    return {"message": "服务端配置已更新", "config": current_config}

# ============================================
# API 路由 - 客户端配置
# ============================================

@app.get("/api/client/config", tags=["客户端"])
async def get_client_config():
    """获取客户端配置"""
    config = read_toml_config(FRPC_CONFIG)
    return config

@app.put("/api/client/config", tags=["客户端"])
async def update_client_config(config: ClientConfig):
    """更新客户端基础配置"""
    current_config = read_toml_config(FRPC_CONFIG)
    
    current_config["serverAddr"] = config.server_addr
    current_config["serverPort"] = config.server_port
    
    if config.token:
        if "auth" not in current_config:
            current_config["auth"] = {}
        current_config["auth"]["method"] = "token"
        current_config["auth"]["token"] = config.token
    
    write_toml_config(FRPC_CONFIG, current_config)
    
    return {"message": "客户端配置已更新", "config": current_config}

# ============================================
# API 路由 - 代理管理
# ============================================

@app.get("/api/proxies", tags=["代理管理"])
async def list_proxies():
    """列出所有代理"""
    config = read_toml_config(FRPC_CONFIG)
    proxies = config.get("proxies", [])
    return {"proxies": proxies, "count": len(proxies)}

@app.post("/api/proxies", tags=["代理管理"])
async def create_proxy(proxy: ProxyCreate):
    """创建新代理"""
    config = read_toml_config(FRPC_CONFIG)
    
    if "proxies" not in config:
        config["proxies"] = []
    
    # 检查名称是否重复
    for p in config["proxies"]:
        if p.get("name") == proxy.name:
            raise HTTPException(status_code=400, detail=f"代理名称 '{proxy.name}' 已存在")
    
    # 构建代理配置
    new_proxy = {
        "name": proxy.name,
        "type": proxy.type,
        "localIP": proxy.local_ip,
        "localPort": proxy.local_port,
    }
    
    if proxy.type in ["tcp", "udp"] and proxy.remote_port:
        new_proxy["remotePort"] = proxy.remote_port
    
    if proxy.type in ["http", "https"]:
        if proxy.custom_domains:
            new_proxy["customDomains"] = proxy.custom_domains
        if proxy.subdomain:
            new_proxy["subdomain"] = proxy.subdomain
    
    config["proxies"].append(new_proxy)
    write_toml_config(FRPC_CONFIG, config)
    
    return {"message": "代理已创建", "proxy": new_proxy}

@app.get("/api/proxies/{proxy_name}", tags=["代理管理"])
async def get_proxy(proxy_name: str):
    """获取指定代理"""
    config = read_toml_config(FRPC_CONFIG)
    proxies = config.get("proxies", [])
    
    for proxy in proxies:
        if proxy.get("name") == proxy_name:
            return proxy
    
    raise HTTPException(status_code=404, detail=f"代理 '{proxy_name}' 不存在")

@app.put("/api/proxies/{proxy_name}", tags=["代理管理"])
async def update_proxy(proxy_name: str, proxy: ProxyCreate):
    """更新代理"""
    config = read_toml_config(FRPC_CONFIG)
    proxies = config.get("proxies", [])
    
    for i, p in enumerate(proxies):
        if p.get("name") == proxy_name:
            # 更新代理
            updated_proxy = {
                "name": proxy.name,
                "type": proxy.type,
                "localIP": proxy.local_ip,
                "localPort": proxy.local_port,
            }
            
            if proxy.type in ["tcp", "udp"] and proxy.remote_port:
                updated_proxy["remotePort"] = proxy.remote_port
            
            if proxy.type in ["http", "https"]:
                if proxy.custom_domains:
                    updated_proxy["customDomains"] = proxy.custom_domains
                if proxy.subdomain:
                    updated_proxy["subdomain"] = proxy.subdomain
            
            config["proxies"][i] = updated_proxy
            write_toml_config(FRPC_CONFIG, config)
            
            return {"message": "代理已更新", "proxy": updated_proxy}
    
    raise HTTPException(status_code=404, detail=f"代理 '{proxy_name}' 不存在")

@app.delete("/api/proxies/{proxy_name}", tags=["代理管理"])
async def delete_proxy(proxy_name: str):
    """删除代理"""
    config = read_toml_config(FRPC_CONFIG)
    proxies = config.get("proxies", [])
    
    for i, p in enumerate(proxies):
        if p.get("name") == proxy_name:
            del config["proxies"][i]
            write_toml_config(FRPC_CONFIG, config)
            return {"message": f"代理 '{proxy_name}' 已删除"}
    
    raise HTTPException(status_code=404, detail=f"代理 '{proxy_name}' 不存在")

# ============================================
# API 路由 - 日志
# ============================================

@app.get("/api/logs/{service_name}", tags=["日志"])
async def get_logs(service_name: str, lines: int = 100):
    """获取服务日志"""
    if service_name == "frps":
        log_path = FRPS_LOG
    elif service_name == "frpc":
        log_path = FRPC_LOG
    else:
        raise HTTPException(status_code=400, detail="无效的服务名称")
    
    return read_log_file(log_path, lines)

# ============================================
# 静态文件服务
# ============================================

# 挂载前端静态文件
frontend_path = Path(__file__).parent.parent / "frontend"
index_file = frontend_path / "index.html"

@app.get("/")
async def serve_frontend():
    if index_file.exists():
        return FileResponse(index_file)
    return {"message": "FRP Panel API", "docs": "/api/docs"}

@app.get("/{full_path:path}")
async def serve_frontend_routes(full_path: str):
    # API 路由不处理
    if full_path.startswith("api/"):
        raise HTTPException(status_code=404)
    
    file_path = frontend_path / full_path
    if file_path.exists() and file_path.is_file():
        return FileResponse(file_path)
    if index_file.exists():
        return FileResponse(index_file)
    raise HTTPException(status_code=404)

# ============================================
# 启动
# ============================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
