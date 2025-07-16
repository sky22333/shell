#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#=======================================================================#
#   系统支持:  Debian 10 + / Ubuntu 18.04 +                             #
#   描述: L2TP VPN 自动安装脚本                                          #
#   基于Teddysun版本修改                                                 #
#=======================================================================#
cur_dir=`pwd`

rootness(){
    if [[ $EUID -ne 0 ]]; then
       echo "错误: 此脚本必须以root身份运行!" 1>&2
       exit 1
    fi
}

tunavailable(){
    if [[ ! -e /dev/net/tun ]]; then
        echo "错误: TUN/TAP 不可用!" 1>&2
        exit 1
    fi
}

disable_selinux(){
if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
fi
}

get_opsy(){
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

get_os_info(){
    IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipinfo.io/ip )
    if [ -z ${IP} ]; then
        IP=$( wget -qO- -t1 -T2 ifconfig.me )
    fi

    local cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
    local freq=$( awk -F: '/cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local tram=$( free -m | awk '/Mem/ {print $2}' )
    local swap=$( free -m | awk '/Swap/ {print $2}' )
    local up=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60;d=$1%60} {printf("%d天 %d:%d:%d\n",a,b,c,d)}' /proc/uptime )
    local load=$( w | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' )
    local opsy=$( get_opsy )
    local arch=$( uname -m )
    local lbit=$( getconf LONG_BIT )
    local host=$( hostname )
    local kern=$( uname -r )

    echo "########## 系统信息 ##########"
    echo 
    echo "CPU型号             : ${cname}"
    echo "CPU核心数           : ${cores}"
    echo "CPU频率             : ${freq} MHz"
    echo "总内存大小          : ${tram} MB"
    echo "总交换分区大小      : ${swap} MB"
    echo "系统运行时间        : ${up}"
    echo "平均负载            : ${load}"
    echo "操作系统            : ${opsy}"
    echo "系统架构            : ${arch} (${lbit} Bit)"
    echo "内核版本            : ${kern}"
    echo "主机名              : ${host}"
    echo "IPv4地址            : ${IP}"
    echo 
    echo "##################################"
}

check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''

    if cat /etc/issue | grep -Eqi "debian"; then
        release="debian"
        systemPackage="apt"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        release="ubuntu"
        systemPackage="apt"
    elif cat /proc/version | grep -Eqi "debian"; then
        release="debian"
        systemPackage="apt"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        release="ubuntu"
        systemPackage="apt"
    else
        echo "错误: 不支持的系统，请使用Debian或Ubuntu系统！"
        exit 1
    fi

    if [[ ${checkType} == "sysRelease" ]]; then
        if [ "$value" == "$release" ];then
            return 0
        else
            return 1
        fi
    elif [[ ${checkType} == "packageManager" ]]; then
        if [ "$value" == "$systemPackage" ];then
            return 0
        else
            return 1
        fi
    fi
}

rand(){
    index=0
    str=""
    for i in {a..z}; do arr[index]=${i}; index=`expr ${index} + 1`; done
    for i in {A..Z}; do arr[index]=${i}; index=`expr ${index} + 1`; done
    for i in {0..9}; do arr[index]=${i}; index=`expr ${index} + 1`; done
    for i in {1..10}; do str="$str${arr[$RANDOM%$index]}"; done
    echo ${str}
}

is_64bit(){
    if [ `getconf WORD_BIT` = '32' ] && [ `getconf LONG_BIT` = '64' ] ; then
        return 0
    else
        return 1
    fi
}

versionget(){
    if [ -f /etc/os-release ];then
        grep -oE  "[0-9.]+" /etc/os-release | head -1
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}

debianversion(){
    if check_sys sysRelease debian;then
        local version=$( get_opsy )
        local code=${1}
        local main_ver=$( echo ${version} | sed 's/[^0-9]//g')
        if [ "${main_ver}" == "${code}" ];then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

version_check(){
    if check_sys packageManager apt; then
        if debianversion 5; then
            echo "错误: Debian 5 不支持，请重新安装OS并重试。"
            exit 1
        fi
    fi
}

get_char(){
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

preinstall_l2tp(){

    echo
    if [ -d "/proc/vz" ]; then
        echo -e "\033[41;37m 警告: \033[0m 您的VPS基于OpenVZ，内核可能不支持IPSec。"
        echo "是否继续安装? (y/n)"
        read -p "(默认: n)" agree
        [ -z ${agree} ] && agree="n"
        if [ "${agree}" == "n" ]; then
            echo
            echo "L2TP安装已取消。"
            echo
            exit 0
        fi
    fi
    echo
    echo "请输入IP范围:"
    read -p "(默认范围: 192.168.18):" iprange
    [ -z ${iprange} ] && iprange="192.168.18"

    echo "请输入PSK密钥:"
    read -p "(默认PSK: admin123@l2tp):" mypsk
    [ -z ${mypsk} ] && mypsk="admin123@l2tp"

    echo "请输入用户名:"
    read -p "(默认用户名: admin123):" username
    [ -z ${username} ] && username="admin123"

    password=`rand`
    echo "请输入 ${username} 的密码:"
    read -p "(默认密码: ${password}):" tmppassword
    [ ! -z ${tmppassword} ] && password=${tmppassword}

    echo
    echo "服务器IP: ${IP}"
    echo "服务器本地IP: ${iprange}.1"
    echo "客户端远程IP范围: ${iprange}.2-${iprange}.254"
    echo "PSK密钥: ${mypsk}"
    echo
    echo "按任意键开始安装...或按Ctrl+C取消。"
    char=`get_char`

}

# 安装依赖
install_l2tp(){
    mknod /dev/random c 1 9
    apt -y update
    apt -yq install curl wget ppp xl2tpd libreswan
    config_install
}

config_install(){

    cat > /etc/ipsec.conf<<EOF
version 2.0

config setup
    protostack=netkey
    nhelpers=0
    uniqueids=no
    interfaces=%defaultroute
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!${iprange}.0/24

conn l2tp-psk
    rightsubnet=vhost:%priv
    also=l2tp-psk-nonat

conn l2tp-psk-nonat
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%defaultroute
    leftid=${IP}
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    dpddelay=40
    dpdtimeout=130
    dpdaction=clear
    sha2-truncbug=yes
EOF

    cat > /etc/ipsec.secrets<<EOF
%any %any : PSK "${mypsk}"
EOF

    cat > /etc/xl2tpd/xl2tpd.conf<<EOF
[global]
port = 1701

[lns default]
ip range = ${iprange}.2-${iprange}.254
local ip = ${iprange}.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    cat > /etc/ppp/options.xl2tpd<<EOF
ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
hide-password
idle 1800
mtu 1410
mru 1410
nodefaultroute
debug
proxyarp
connect-delay 5000
EOF

    rm -f /etc/ppp/chap-secrets
    cat > /etc/ppp/chap-secrets<<EOF
# Secrets for authentication using CHAP
# client    server    secret    IP addresses
${username}    l2tpd    ${password}       *
EOF

    cp -pf /etc/sysctl.conf /etc/sysctl.conf.bak

    sed -i 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf

    for each in `ls /proc/sys/net/ipv4/conf/`; do
        echo "net.ipv4.conf.${each}.accept_source_route=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.accept_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.send_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.rp_filter=0" >> /etc/sysctl.conf
    done
    sysctl -p

    [ -f /etc/iptables.rules ] && cp -pf /etc/iptables.rules /etc/iptables.rules.old.`date +%Y%m%d`

    # 确保IP变量已正确获取
    if [ -z "${IP}" ]; then
        IP=$(wget -qO- ipinfo.io/ip)
    fi

    cat > /etc/iptables.rules <<EOF
# Added by L2TP VPN script
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p udp -m multiport --dports 500,4500,1701 -j ACCEPT
-A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -s ${iprange}.0/24 -j ACCEPT
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s ${iprange}.0/24 -j SNAT --to-source ${IP}
COMMIT
EOF

    # 创建rc.local文件（如果不存在）
    if [ ! -f /etc/rc.local ]; then
        cat > /etc/rc.local <<EOF
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

echo 1 > /proc/sys/net/ipv4/ip_forward
/usr/sbin/service ipsec start
/usr/sbin/service xl2tpd start
/sbin/iptables-restore < /etc/iptables.rules

exit 0
EOF
        chmod +x /etc/rc.local
    else
        # 如果已存在rc.local，则追加内容
        sed -i '/^exit 0/d' /etc/rc.local
        cat >> /etc/rc.local <<EOF

# Added by L2TP VPN script
echo 1 > /proc/sys/net/ipv4/ip_forward
/usr/sbin/service ipsec start
/usr/sbin/service xl2tpd start
/sbin/iptables-restore < /etc/iptables.rules

exit 0
EOF
    fi

    cat > /etc/network/if-up.d/iptables <<EOF
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.rules
EOF
    chmod +x /etc/network/if-up.d/iptables

    if [ ! -f /etc/ipsec.d/cert9.db ]; then
       echo > /var/tmp/libreswan-nss-pwd
       certutil -N -f /var/tmp/libreswan-nss-pwd -d /etc/ipsec.d
       rm -f /var/tmp/libreswan-nss-pwd
    fi

    update-rc.d -f xl2tpd defaults

    # 启用并启动服务
    systemctl enable ipsec
    systemctl enable xl2tpd

    echo 1 > /proc/sys/net/ipv4/ip_forward
    /sbin/iptables-restore < /etc/iptables.rules
    systemctl restart ipsec
    systemctl restart xl2tpd
}

finally(){
    cp -f ${cur_dir}/l2tp.sh /usr/bin/l2tp 2>/dev/null || true
    echo "请稍候..."
    sleep 3
    ipsec verify
    echo
    echo "###############################################################"
    echo "# L2TP 安装脚本                                               #"
    echo "###############################################################"
    echo
    echo "默认用户名和密码如下:"
    echo
    echo "服务器IP: ${IP}"
    echo "PSK密钥 : ${mypsk}"
    echo "用户名  : ${username}"
    echo "密码    : ${password}"
    echo
    echo "如果您想修改用户设置，请使用以下命令:"
    echo "-a (添加用户)"
    echo "-d (删除用户)"
    echo "-l (列出所有用户)"
    echo "-m (修改用户密码)"
    echo
}


l2tp(){
    clear
    echo
    echo "###############################################################"
    echo "# L2TP 安装脚本                                               #"
    echo "###############################################################"
    echo
    rootness
    tunavailable
    disable_selinux
    version_check
    get_os_info
    preinstall_l2tp
    install_l2tp
    finally
}

list_users(){
    if [ ! -f /etc/ppp/chap-secrets ];then
        echo "错误: /etc/ppp/chap-secrets 文件未找到."
        exit 1
    fi
    local line="+-------------------------------------------+\n"
    local string=%20s
    printf "${line}|${string} |${string} |\n${line}" 用户名 密码
    grep -v "^#" /etc/ppp/chap-secrets | awk '{printf "|'${string}' |'${string}' |\n", $1,$3}'
    printf ${line}
}

add_user(){
    while :
    do
        read -p "请输入用户名:" user
        if [ -z ${user} ]; then
            echo "用户名不能为空"
        else
            grep -w "${user}" /etc/ppp/chap-secrets > /dev/null 2>&1
            if [ $? -eq 0 ];then
                echo "用户名 (${user}) 已存在。请重新输入用户名。"
            else
                break
            fi
        fi
    done
    pass=`rand`
    echo "请输入 ${user} 的密码:"
    read -p "(默认密码: ${pass}):" tmppass
    [ ! -z ${tmppass} ] && pass=${tmppass}
    echo "${user}    l2tpd    ${pass}       *" >> /etc/ppp/chap-secrets
    echo "用户 (${user}) 添加完成。"
}

del_user(){
    while :
    do
        read -p "请输入要删除的用户名:" user
        if [ -z ${user} ]; then
            echo "用户名不能为空"
        else
            grep -w "${user}" /etc/ppp/chap-secrets >/dev/null 2>&1
            if [ $? -eq 0 ];then
                break
            else
                echo "用户名 (${user}) 不存在。请重新输入用户名。"
            fi
        fi
    done
    sed -i "/^\<${user}\>/d" /etc/ppp/chap-secrets
    echo "用户 (${user}) 删除完成。"
}

mod_user(){
    while :
    do
        read -p "请输入要修改密码的用户名:" user
        if [ -z ${user} ]; then
            echo "用户名不能为空"
        else
            grep -w "${user}" /etc/ppp/chap-secrets >/dev/null 2>&1
            if [ $? -eq 0 ];then
                break
            else
                echo "用户名 (${user}) 不存在。请重新输入用户名。"
            fi
        fi
    done
    pass=`rand`
    echo "请输入 ${user} 的新密码:"
    read -p "(默认密码: ${pass}):" tmppass
    [ ! -z ${tmppass} ] && pass=${tmppass}
    sed -i "/^\<${user}\>/d" /etc/ppp/chap-secrets
    echo "${user}    l2tpd    ${pass}       *" >> /etc/ppp/chap-secrets
    echo "用户 ${user} 的密码已更改。"
}

# 主程序
action=$1
if [ -z ${action} ] && [ "`basename $0`" != "l2tp" ]; then
    action=install
fi

case ${action} in
    install)
        l2tp 2>&1 | tee ${cur_dir}/l2tp.log
        ;;
    -l|--list)
        list_users
        ;;
    -a|--add)
        add_user
        ;;
    -d|--del)
        del_user
        ;;
    -m|--mod)
        mod_user
        ;;
    -h|--help)
        echo "用法:  -l,--list   列出所有用户"
        echo "       -a,--add    添加用户"
        echo "       -d,--del    删除用户"
        echo "       -m,--mod    修改用户密码"
        echo "       -h,--help   打印此帮助信息"
        ;;
    *)
        echo "用法: [-l,--查看用户|-a,--添加用户|-d,--删除用户|-m,--修改密码|-h,--帮助信息]" && exit
        ;;
esac
