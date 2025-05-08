#!/bin/bash

# Socat 管理脚本
# 版本 v2.0
# 主目录: /usr/local/socat
# 日志目录: /usr/local/socat/logs

MAIN_DIR="/usr/local/socat"
LOG_DIR="$MAIN_DIR/logs"

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请以 root 用户运行此脚本"
    exit 1
fi

# 创建主目录和日志目录
mkdir -p "$LOG_DIR"

# 检查包管理器类型
if command -v apt-get >/dev/null 2>&1; then
    PKG_INSTALL="apt-get install -y"
    PKG_REMOVE="apt-get remove -y"
    PKG_UPDATE="apt-get update -y"
elif command -v yum >/dev/null 2>&1; then
    PKG_INSTALL="yum install -y"
    PKG_REMOVE="yum remove -y"
    PKG_UPDATE="yum makecache"
elif command -v dnf >/dev/null 2>&1; then
    PKG_INSTALL="dnf install -y"
    PKG_REMOVE="dnf remove -y"
    PKG_UPDATE="dnf makecache"
else
    PKG_INSTALL=""
    PKG_REMOVE=""
fi

# 安装 socat
install_socat() {
    echo "安装 socat..."
    if command -v socat >/dev/null 2>&1; then
        echo "socat 已经安装！"
    else
        if [ -n "$PKG_INSTALL" ]; then
            $PKG_UPDATE
            $PKG_INSTALL socat
            if [ $? -eq 0 ]; then
                echo "socat 安装成功！"
            else
                echo "socat 安装失败，请检查网络或源设置。"
            fi
        else
            echo "无法识别的操作系统，请手动安装 socat。"
        fi
    fi
    read -p "按任意键返回主菜单..." temp
}

# 卸载 socat 及清除所有转发服务
uninstall_socat() {
    echo "警告：将卸载 socat 并删除所有转发服务和日志！"
    read -p "确认继续？ [y/n]: " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "取消卸载。"
        read -p "按任意键返回主菜单..." temp
        return
    fi

    echo "停止并删除所有转发服务..."
    if ls /etc/systemd/system/socat-*.service >/dev/null 2>&1; then
        for svc in /etc/systemd/system/socat-*.service; do
            svcname=$(basename "$svc")
            systemctl stop "$svcname"
            systemctl disable "$svcname"
            rm -f "$svc"
        done
        systemctl daemon-reload
    fi

    echo "删除日志文件和主目录..."
    rm -rf "$MAIN_DIR"

    echo "卸载 socat 软件包..."
    if [ -n "$PKG_REMOVE" ]; then
        $PKG_REMOVE socat
    else
        echo "无法识别的操作系统，请手动卸载 socat。"
    fi

    echo "卸载完成。"
    read -p "按任意键退出..." temp
    exit 0
}

# 添加端口转发服务
add_port_forward() {
    echo "添加新的端口转发服务"
    read -p "请输入本地监听端口: " LPORT
    if ! [[ "$LPORT" =~ ^[0-9]+$ ]]; then
        echo "端口号必须为数字！"
        read -p "按任意键返回主菜单..." temp
        return
    fi
    if ss -tulpn | grep -q ":$LPORT\b"; then
        echo "端口 $LPORT 已被占用，请选择其他端口。"
        read -p "按任意键返回主菜单..." temp
        return
    fi

    read -p "请输入远程目标地址或主机名: " RADDR
    if [ -z "$RADDR" ]; then
        echo "远程地址不能为空！"
        read -p "按任意键返回主菜单..." temp
        return
    fi
    read -p "请输入远程目标端口: " RPORT
    if ! [[ "$RPORT" =~ ^[0-9]+$ ]]; then
        echo "端口号必须为数字！"
        read -p "按任意键返回主菜单..." temp
        return
    fi

    # 生成服务名称
    safe_remote=$(echo "$RADDR" | sed 's/[^A-Za-z0-9]/_/g')
    SERVICE_NAME="socat-$LPORT-$safe_remote-$RPORT.service"
    SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
    LOG_PATH="$LOG_DIR/${SERVICE_NAME%.service}.log"

    if [ -f "$SERVICE_PATH" ]; then
        echo "服务已存在：$SERVICE_NAME"
        read -p "按任意键返回主菜单..." temp
        return
    fi

    # 创建 systemd 服务文件
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Socat 转发 $LPORT -> $RADDR:$RPORT
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c "/usr/bin/socat TCP4-LISTEN:$LPORT,reuseaddr,fork TCP4:$RADDR:$RPORT >> $LOG_PATH 2>&1"
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo "服务文件已创建：$SERVICE_NAME"

    read -p "是否立即启动该服务？ [y/n]: " ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
        systemctl start "$SERVICE_NAME"
        if [ $? -eq 0 ]; then
            echo "服务 $SERVICE_NAME 已启动。日志输出在 $LOG_PATH"
        else
            echo "服务启动失败，请检查服务文件或日志。"
        fi
    fi

    read -p "按任意键返回主菜单..." temp
}

# 查看日志
view_logs() {
    echo "查看日志"
    logs=( "$LOG_DIR"/*.log )
    if [ ! -e "${logs[0]}" ]; then
        echo "暂无日志文件。"
        read -p "按任意键返回主菜单..." temp
        return
    fi

    echo "日志列表："
    select logfile in "${logs[@]}" "返回"; do
        if [ -z "$logfile" ]; then
            echo "无效选择。"
        elif [ "$logfile" = "返回" ]; then
            break
        else
            echo "显示日志：$logfile (最后 100 行)"
            echo "============================"
            tail -n 100 "$logfile"
            echo "============================"
            read -p "按任意键继续..." temp
        fi
    done
}

# 列出转发服务并管理
manage_services() {
    while true; do
        echo "转发服务列表："
        services=( $(ls /etc/systemd/system/socat-*.service 2>/dev/null) )
        if [ ${#services[@]} -eq 0 ]; then
            echo "当前没有已配置的转发服务。"
            read -p "按任意键返回主菜单..." temp
            return
        fi
        count=0
        for svc in "${services[@]}"; do
            name=$(basename "$svc")
            parts=( $(echo "${name%.service}" | tr '-' ' ') )
            lport=${parts[1]}
            remote_safe=${parts[2]}
            rport=${parts[3]}
            remote=${remote_safe//_/\.}
            ((count++))
            echo "$count) 本地 $lport -> 远程 $remote:$rport"
        done
        echo "$((count+1))) 返回主菜单"
        read -p "请选择服务序号进行管理: " sel
        if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt $((count+1)) ]; then
            echo "无效选择，请重新输入。"
            continue
        fi
        if [ "$sel" -eq $((count+1)) ]; then
            break
        fi
        svc_file=${services[$((sel-1))]}
        svc_name=$(basename "$svc_file")
        while true; do
            echo "管理服务：$svc_name"
            echo "1) 启动服务"
            echo "2) 停止服务"
            echo "3) 重启服务"
            echo "4) 启用开机自启"
            echo "5) 禁用开机自启"
            echo "6) 删除服务"
            echo "7) 返回上级菜单"
            read -p "请选择操作 [1-7]: " op
            case "$op" in
                1)
                    systemctl start "$svc_name"
                    echo "已启动 $svc_name"
                    ;;
                2)
                    systemctl stop "$svc_name"
                    echo "已停止 $svc_name"
                    ;;
                3)
                    systemctl restart "$svc_name"
                    echo "已重启 $svc_name"
                    ;;
                4)
                    systemctl enable "$svc_name"
                    echo "已启用 $svc_name 开机自启"
                    ;;
                5)
                    systemctl disable "$svc_name"
                    echo "已禁用 $svc_name 开机自启"
                    ;;
                6)
                    read -p "确认删除服务 $svc_name? [y/n]: " del_ans
                    if [ "$del_ans" = "y" ] || [ "$del_ans" = "Y" ]; then
                        systemctl stop "$svc_name"
                        systemctl disable "$svc_name"
                        rm -f "$svc_file"
                        # 删除日志文件
                        logf="$LOG_DIR/${svc_name%.service}.log"
                        [ -f "$logf" ] && rm -f "$logf"
                        systemctl daemon-reload
                        echo "服务 $svc_name 已删除。"
                        break
                    else
                        echo "取消删除。"
                    fi
                    ;;
                7)
                    break
                    ;;
                *)
                    echo "无效选项。"
                    ;;
            esac
            read -p "按任意键继续..." temp
        done
    done
}

# 使用帮助
aboat_help() {
   clear
     echo "-----使用说明-----"
     echo  ""
     echo "Github：https://github.com/99u/socat/ "
      echo ""
      echo ""
     read -p "按任意键返回主菜单..." temp
}

# 主菜单
while true; do
clear
    echo "======================================"
    echo "        socat 转发 管理脚本"
    echo "                  By vv1234.cn   "
    echo "======================================"
    echo "1) 安装 socat"
    echo "2) 卸载 socat"
    echo "3) 添加端口转发"
    echo "4) 查看日志"
    echo "5) 列出转发服务列表"
    echo "6) 使用帮助"
    echo "0) 退出"
    read -p "请选择 [1-6]: " choice
    case "$choice" in
        1) install_socat ;;
        2) uninstall_socat ;;
        3) add_port_forward ;;
        4) view_logs ;;
        5) manage_services ;;
        6) aboat_help ;;
        0) echo "退出." ; exit 0 ;;
        *) echo "无效选项，请重新选择。" ;;
    esac
done
