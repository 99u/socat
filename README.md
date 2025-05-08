主要功能/特性

1，使用Socat进行端口转发

2，兼容主流Linux操作系统

3，交互式可视化界面风格


安装运行

root下执行脚本

```if [ -f /usr/bin/curl ];then curl -sSO https://raw.githubusercontent.com/99u/socat/refs/heads/main/socat.sh;else wget -O socat.sh https://raw.githubusercontent.com/99u/socat/refs/heads/main/socat.sh;fi;bash socat.sh```

运行截图

 
![image](https://github.com/user-attachments/assets/acaf11a1-1645-4031-9c94-dc7ceecc0150)


注意事项，如启用了防火墙，需放行端口，如宝塔面板，需在安全-系统防火墙-添加端口放行规则.

详见 [https://vv1234.cn/archives/944.html](https://vv1234.cn/archives/944.html)
