#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印颜色输出函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行，请使用 sudo 执行"
        exit 1
    fi
}

# 自动识别 VPS 的核心和内存数
detect_system_info() {
    # 获取CPU核心数
    CPU_CORES=$(nproc)
    if [[ $CPU_CORES -eq 0 ]]; then
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
    fi
    
    # 获取系统内存（KB）
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
    TOTAL_MEM_GB=$((TOTAL_MEM_MB / 1024))
    
    # 获取系统架构
    ARCH=$(uname -m)
    
    # 获取内核版本
    KERNEL_VERSION=$(uname -r)
    
    print_success "系统信息检测完成:"
    echo "=========================================="
    echo "CPU 核心数    : $CPU_CORES 核心"
    echo "内存总量     : $TOTAL_MEM_MB MB ($TOTAL_MEM_GB GB)"
    echo "系统架构     : $ARCH"
    echo "内核版本     : $KERNEL_VERSION"
    echo "=========================================="
}

# 动态参数计算函数（按照等级分类）
calculate_parameters() {
    print_info "根据系统配置计算优化参数..."
    
    # 根据内存大小按照等级分类计算TCP内存参数
    if [[ $TOTAL_MEM_MB -le 512 ]]; then
        # (≤512MB)内存
        tcp_mem_min=98304
        tcp_mem_pressure=131072
        tcp_mem_max=196608
        rmem_max=16777216
        wmem_max=16777216
        print_info "检测到(≤512MB)内存系统"
    elif [[ $TOTAL_MEM_MB -le 1024 ]]; then
        # (512MB-1GB)内存
        tcp_mem_min=196608
        tcp_mem_pressure=262144
        tcp_mem_max=393216
        rmem_max=33554432
        wmem_max=33554432
        print_info "检测到(512MB-1GB)内存系统"
    elif [[ $TOTAL_MEM_MB -le 2048 ]]; then
        # (1GB-2GB)内存
        tcp_mem_min=262144
        tcp_mem_pressure=393216
        tcp_mem_max=524288
        rmem_max=50331648
        wmem_max=50331648
        print_info "检测到(1GB-2GB)内存系统"
    elif [[ $TOTAL_MEM_MB -le 4096 ]]; then
        # (2GB-4GB)内存
        tcp_mem_min=393216
        tcp_mem_pressure=524288
        tcp_mem_max=786432
        rmem_max=67108864
        wmem_max=67108864
        print_info "检测到(2GB-4GB)内存系统"
    elif [[ $TOTAL_MEM_MB -le 8192 ]]; then
        # (4GB-8GB)内存
        tcp_mem_min=524288
        tcp_mem_pressure=786432
        tcp_mem_max=1048576
        rmem_max=100663296
        wmem_max=100663296
        print_info "检测到(4GB-8GB)内存系统"
    else
        # (>8GB)内存
        tcp_mem_min=786432
        tcp_mem_pressure=1048576
        tcp_mem_max=1572864
        rmem_max=134217728
        wmem_max=134217728
        print_info "检测到(>8GB)内存系统"
    fi
    
    # 根据CPU核心数调整连接数参数
    if [[ $CPU_CORES -le 2 ]]; then
        BACKLOG=8192
        SOMAXCONN=16384
        MAX_TW_BUCKETS=1000000
    elif [[ $CPU_CORES -le 4 ]]; then
        BACKLOG=16384
        SOMAXCONN=32768
        MAX_TW_BUCKETS=1500000
    else
        BACKLOG=65536
        SOMAXCONN=65535
        MAX_TW_BUCKETS=2000000
    fi
    
    # TCP读写缓冲区设置
    tcp_rmem_min=4096
    tcp_rmem_default=262144
    tcp_rmem_max=$rmem_max
    
    tcp_wmem_min=4096
    tcp_wmem_default=262144
    tcp_wmem_max=$wmem_max
    
    # 核心缓冲区设置
    core_rmem_default=262144
    core_wmem_default=262144
    core_rmem_max=$rmem_max
    core_wmem_max=$wmem_max
    core_optmem_max=65536
    
    # 根据内存大小调整文件句柄限制
    if [[ $TOTAL_MEM_MB -le 1024 ]]; then
        FILE_MAX=512000
        SOFT_NOFILE=102400
        HARD_NOFILE=204800
    elif [[ $TOTAL_MEM_MB -le 4096 ]]; then
        FILE_MAX=1024000
        SOFT_NOFILE=512000
        HARD_NOFILE=1024000
    else
        FILE_MAX=2048000
        SOFT_NOFILE=1024000
        HARD_NOFILE=2048000
    fi
    
    print_success "参数计算完成"
    
    # 显示计算出的参数
    echo ""
    print_info "=== 优化参数详情 ==="
    echo "TCP内存参数    : $tcp_mem_min $tcp_mem_pressure $tcp_mem_max"
    echo "TCP读缓冲区   : $tcp_rmem_min $tcp_rmem_default $tcp_rmem_max"
    echo "TCP写缓冲区   : $tcp_wmem_min $tcp_wmem_default $tcp_wmem_max"
    echo "连接积压队列   : $BACKLOG"
    echo "最大连接数    : $SOMAXCONN"
    echo "TIME_WAIT数量 : $MAX_TW_BUCKETS"
    echo "文件句柄限制  : $FILE_MAX"
    echo "========================="
}

# 检查系统类型
check_os() {
    if [ -f /etc/redhat-release ]; then
        OS="centos"
    elif grep -Eqi "debian" /etc/issue; then
        OS="debian"
    elif grep -Eqi "ubuntu" /etc/issue; then
        OS="ubuntu"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
        OS="centos"
    elif grep -Eqi "debian" /proc/version; then
        OS="debian"
    elif grep -Eqi "ubuntu" /proc/version; then
        OS="ubuntu"
    elif grep -Eqi "centos|red hat|redhat" /proc/version; then
        OS="centos"
    else
        print_error "不支持的系统类型"
        exit 1
    fi
    print_info "检测到系统: $OS"
}

# 检查BBR支持
check_bbr_support() {
    print_info "检查BBR支持情况..."
    
    # 检查内核版本
    local KERNEL_MAJOR=$(uname -r | cut -d. -f1)
    local KERNEL_MINOR=$(uname -r | cut -d. -f2)
    
    if [[ $KERNEL_MAJOR -lt 4 ]] || ([[ $KERNEL_MAJOR -eq 4 ]] && [[ $KERNEL_MINOR -lt 9 ]]); then
        print_warning "当前内核版本 $KERNEL_VERSION 低于4.9，BBR可能无法正常工作"
        print_warning "建议升级内核以获得最佳性能"
        read -p "是否继续安装？(y/N): " continue_install
        if [[ ! $continue_install =~ ^[Yy]$ ]]; then
            print_info "安装已取消"
            exit 0
        fi
    else
        print_success "内核版本支持 BBR"
    fi
    
    # 检查BBR模块
    if modprobe tcp_bbr 2>/dev/null; then
        print_success "BBR模块可用"
    else
        print_error "BBR模块不可用，请检查内核配置"
        exit 1
    fi
}

# 安装BBR
install_bbr() {
    print_info "开始安装BBR..."
    
    # 检查BBR支持
    check_bbr_support
    
    # 检测系统信息
    detect_system_info
    
    # 计算动态参数
    calculate_parameters
    
    # 备份原有配置
    if [[ -f /etc/sysctl.conf ]]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d%H%M%S)
        print_success "已备份原有sysctl配置"
    fi

    # 加载BBR模块
    modprobe tcp_bbr
    if lsmod | grep -q bbr; then
        print_success "BBR模块加载成功"
    else
        print_error "BBR模块加载失败"
        return 1
    fi

    # 应用TCP/IP优化配置
    apply_tcp_optimizations
}

# 应用TCP/IP优化配置
apply_tcp_optimizations() {
    print_info "应用TCP/IP优化配置..."
    
    # 创建优化配置文件
    cat > /etc/sysctl.d/99-tcp-optimizations.conf << EOF
# TCP BBR 配置
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 网络缓冲区优化
net.core.rmem_max = $core_rmem_max
net.core.wmem_max = $core_wmem_max
net.core.rmem_default = $core_rmem_default
net.core.wmem_default = $core_wmem_default
net.core.optmem_max = $core_optmem_max

# TCP缓冲区优化
net.ipv4.tcp_rmem = $tcp_rmem_min $tcp_rmem_default $tcp_rmem_max
net.ipv4.tcp_wmem = $tcp_wmem_min $tcp_wmem_default $tcp_wmem_max
net.ipv4.tcp_mem = $tcp_mem_min $tcp_mem_pressure $tcp_mem_max

# TCP连接优化（根据CPU核心数动态调整）
net.ipv4.tcp_max_syn_backlog = $BACKLOG
net.ipv4.tcp_max_tw_buckets = $MAX_TW_BUCKETS
net.core.somaxconn = $SOMAXCONN
net.core.netdev_max_backlog = $BACKLOG

# TCP性能优化
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1

# 文件句柄优化（根据内存大小动态调整）
fs.file-max = $FILE_MAX
EOF

    # 应用配置
    sysctl -p /etc/sysctl.d/99-tcp-optimizations.conf > /dev/null 2>&1
    
    # 设置开机自动加载
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    
    # 优化文件句柄限制
    if ! grep -q "fs.file-max" /etc/security/limits.conf; then
        echo "* soft nofile $SOFT_NOFILE" >> /etc/security/limits.conf
        echo "* hard nofile $HARD_NOFILE" >> /etc/security/limits.conf
        echo "root soft nofile $SOFT_NOFILE" >> /etc/security/limits.conf
        echo "root hard nofile $HARD_NOFILE" >> /etc/security/limits.conf
    fi
    
    print_success "TCP/IP优化配置已应用"
}

# 检查BBR状态
check_bbr_status() {
    print_info "检查BBR状态..."
    
    # 显示系统信息
    detect_system_info
    
    # 检查BBR是否已启用
    local bbr_status=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [[ "$bbr_status" == "bbr" ]]; then
        print_success "BBR 已启用"
    else
        print_warning "BBR 未启用，当前拥塞控制算法: $bbr_status"
    fi
    
    # 检查队列规则
    local qdisc=$(sysctl net.core.default_qdisc | awk '{print $3}')
    if [[ "$qdisc" == "fq" ]]; then
        print_success "队列规则已优化: $qdisc"
    else
        print_warning "队列规则未优化: $qdisc"
    fi
    
    # 显示关键参数
    echo ""
    print_info "当前TCP参数状态:"
    sysctl net.ipv4.tcp_available_congestion_control
    sysctl net.ipv4.tcp_rmem
    sysctl net.ipv4.tcp_wmem
    sysctl net.ipv4.tcp_mem
    sysctl net.core.somaxconn
    sysctl net.ipv4.tcp_max_syn_backlog
}

# 卸载BBR
uninstall_bbr() {
    print_warning "开始卸载BBR配置..."
    
    # 显示当前系统信息
    detect_system_info
    
    read -p "确定要卸载BBR优化配置吗？(y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_info "取消卸载"
        return
    fi
    
    # 删除优化配置文件
    if [[ -f /etc/sysctl.d/99-tcp-optimizations.conf ]]; then
        rm -f /etc/sysctl.d/99-tcp-optimizations.conf
        print_success "已删除TCP优化配置文件"
    fi
    
    # 恢复默认拥塞控制
    sysctl -w net.ipv4.tcp_congestion_control=cubic > /dev/null 2>&1
    sysctl -w net.core.default_qdisc=pfifo_fast > /dev/null 2>&1
    
    # 从启动配置中移除BBR设置
    if [[ -f /etc/modules-load.d/modules.conf ]]; then
        sed -i '/tcp_bbr/d' /etc/modules-load.d/modules.conf
    fi
    
    # 重新加载sysctl配置
    sysctl -p > /dev/null 2>&1
    
    print_success "BBR配置已卸载"
}

# 显示菜单
show_menu() {
    echo "========================================"
    echo "        TCP/IP & BBR 智能优化脚本"
    echo "========================================"
    echo "1. 安装并优化"
    echo "2. 卸载优化配置"
    echo "3. 检查系统信息和优化状态"
    echo "4. 退出"
    echo "========================================"
}

# 主函数
main() {
    check_root
    check_os
    
    while true; do
        show_menu
        read -p "请选择操作 [1-4]: " choice
        
        case $choice in
            1)
                print_info "开始安装TCP/IP & BBR优化..."
                install_bbr
                check_bbr_status
                
                echo ""
                print_warning "安装完成！部分配置需要重启系统才能完全生效。"
                print_info "如需完全生效，请手动执行: sudo reboot"
                ;;
            2)
                uninstall_bbr
                ;;
            3)
                check_bbr_status
                ;;
            4)
                print_info "退出脚本"
                exit 0
                ;;
            *)
                print_error "无效选择，请重新输入"
                ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
    done
}

# 脚本开始
print_info "TCP/IP & BBR 智能优化脚本启动"
print_info "正在自动检测系统配置..."
main
