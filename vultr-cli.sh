#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
ln -sf ~/sh.sh /usr/local/bin/t
# 检查是否安装了 wget 工具，如果没有则安装
check_wget() {
    if ! command -v wget &> /dev/null; then
        echo "wget is not installed. Installing..."
        sudo apt update
        sudo apt install -y wget
    fi
}
# 安装 Vultr CLI 的函数
install_vultr_cli() {
    # 检查是否已安装 Vultr CLI
    clear
    if command -v vultr-cli &> /dev/null; then
        echo "Vultr CLI 已安装"
        return
    fi
    check_wget    
    # 指定要安装的 Vultr CLI 版本
    local VULTR_CLI_VERSION="v3.3.1"
    local DOWNLOAD_URL="https://github.com/vultr/vultr-cli/releases/download/${VULTR_CLI_VERSION}/vultr-cli_${VULTR_CLI_VERSION}_linux_amd64.tar.gz"
    
    # 下载 Vultr CLI
    wget $DOWNLOAD_URL
    # 解压文件
    tar -zxvf vultr-cli_${VULTR_CLI_VERSION}_linux_amd64.tar.gz
    # 移动二进制文件到 PATH 可访问的位置
    sudo mv vultr-cli /usr/local/bin/
    # 设置执行权限
    sudo chmod +x /usr/local/bin/vultr-cli
    # 清理下载的压缩文件
    rm vultr-cli_${VULTR_CLI_VERSION}_linux_amd64.tar.gz
    
    # 验证安装成功
    echo "Vultr CLI 安装成功!"
}
input_vultr_token(){
    # 获取用户的 Vultr API 令牌
    #read -p "请输入你的 Vultr Token : " VULTR_API_KEY
    read -p $'\e[1;33m请输入你的 Vultr Token : \e[0m' VULTR_API_KEY
    export VULTR_API_KEY=$VULTR_API_KEY
    echo 'export VULTR_API_KEY='"$VULTR_API_KEY" >> ~/.bashrc
    source ~/.bashrc
}
validate_vultr_token(){
    # 获取 Vultr 账户信息
    # 如果 API 令牌无效或 IP 地址未授权，则提示用户重新输入
    if [[ $(vultr-cli account) == *"Unauthorized IP address"* ]]; then
        #echo "请在网页端放行该IP地址，之后重新运行脚本。"
        echo $'\e[1;33m请在网页端放行该IP地址，之后重新运行脚本。\e[0m'
        exit 1
    elif [[ $(vultr-cli account) == *"Invalid API token"* ]]; then
        #echo "请仔细核对token是否正确，之后重新运行脚本。"
        echo $'\e[1;33m请仔细核对token是否正确，之后重新运行脚本。\e[0m'
        exit 1
    else
        # 显示账户信息
        clear
        #vultr-cli account | awk 'BEGIN {print "账户信息:"} NR==2 {printf("余额: %.2f\n待支付: %.2f\n", $1, $2)}'
        #vultr-cli account | awk 'BEGIN {print "\e[1;33m账户信息:\e[0m"} NR==2 {printf("余额: %.2f\n待支付: %.2f\n", $1, $2)}'
        echo -e "\e[1;33mvultr账户信息:\e[0m"
        vultr-cli account | awk 'NR==2 {printf("账户余额: %.2f\n本月已消费: %.2f\n", $1, $2)}'
        return 0
    fi
}
# 添加实例
add_instance() {
    clear
    read -p $'\e[1;35m输入实例名称: \e[0m' label
    # 显示地区选择菜单
#echo "请选择国家或地区"
echo -e "${GREEN}-----------------------选择国家或地区-----------------------${NC}"
echo -e ""
echo -e "\e[1;33m亚洲地区：\e[0m"
echo "1. 新加坡新加坡 (sgp)             5. 印度德里 (del)"
echo "2. 日本东京 (nrt)                 6. 印度孟买 (bom)"
echo "3. 日本大阪 (itm)                 7. 韩国首尔 (icn)"
echo "4. 印度班加罗尔 (blr)             8. 以色列特拉维夫 (tlv)"

echo -e "\e[1;33m美洲地区：\e[0m"
echo "9. 美国迈阿密 (mia)              16. 美国硅谷 (sjc)"
echo "10. 美国亚特兰大 (atl)           17. 美国新泽西州 (ewr)"
echo "11. 美国芝加哥 (ord)             18. 加拿大多伦多 (yto)"
echo "12. 美国达拉斯 (dfw)             19. 智利圣地亚哥 (scl)"
echo "13. 美国洛杉矶 (lax)             20. 巴西圣保罗 (sao)"
echo "14. 美国西雅图 (sea)             21. 墨西哥墨西哥城 (mex)"
echo "15. 美国(夏威夷)檀香山 (hnl)"

echo -e "\e[1;33m欧洲地区：\e[0m"
echo "22. 荷兰阿姆斯特丹 (ams)         26. 西班牙马德里 (mad)"
echo "23. 法国巴黎 (cdg)               27. 英国曼彻斯特 (man)"
echo "24. 德国法兰克福 (fra)           28. 波兰华沙 (waw)"
echo "25. 英国伦敦 (lhr)               29. 瑞典斯德哥尔摩 (sto)"

echo -e "\e[1;33m澳洲地区：\e[0m"
echo "30. 澳大利亚墨尔本 (mel)"
echo "31. 澳大利亚悉尼 (syd)"
echo -e "\e[1;33m非洲地区：\e[0m"
echo "32. 南非约翰内斯堡 (jnb)" | pr -t -2
echo -e ""
echo -e "${GREEN}----------------------------------------------------------${NC}"

    echo -e "\e[1;35m输入对应的数字选择国家和地区:\e[0m"
    read -r region_choice
    clear
    # 根据用户的选择设置相应的地区代码
    case $region_choice in
        1) region="sgp";;
        2) region="nrt";;
        3) region="itm";;
        4) region="blr";;
        5) region="del";;
        6) region="bom";;
        7) region="icn";;
        8) region="tlv";;
        9) region="mia";;
        10) region="atl";;
        11) region="ord";;
        12) region="dfw";;
        13) region="lax";;
        14) region="sea";;
        15) region="hnl";;
        16) region="sjc";;
        17) region="ewr";;
        18) region="yto";;
        19) region="scl";;
        20) region="sao";;
        21) region="mex";;
        22) region="ams";;     
        23) region="cdg";;
        24) region="fra";;
        25) region="lhr";;
        26) region="mad";;
        27) region="man";;
        28) region="waw";;
        29) region="sto";;
        30) region="mel";;
        31) region="syd";;   
        32) region="jnb";;

        *) echo "无效的选择"; return;;
    esac
    
    # 显示系统选择菜单
    #echo "请选择系统: "
    #echo -e "\e[1;33m请选择系统编号:\e[0m"
    echo -e "${GREEN}----------------------选择系统----------------------${NC}"
    echo -e ""
    echo "1. Debian 12 x64 (bookworm)"
    echo "2. Debian 11 x64 (bullseye)"
    echo "3. Debian 10 x64 (buster)"
    echo "4. Ubuntu 23.10 x64"
    echo "5. Ubuntu 22.04 LTS x64"
    echo "6. Ubuntu 20.04 LTS x64"
    echo "7. CentOS 7 x64"
    echo "8. CentOS 7 SELinux x64"
    echo "9. Fedora CoreOS Stable"
    echo "10. CentOS 8 Stream x64"
    echo "11. Arch Linux x64"
    echo "12. Alpine Linux x64"
    echo -e ""
    echo -e "${GREEN}-------------------------------------------------------${NC}"
    #echo "请输入选择编号: "
    echo -e "\e[1;33m请输入系统编号: \e[0m"
    read -r os_choice
    clear
    # 根据用户的选择设置相应的操作系统代码
    case $os_choice in
        1) os=2136;;
        2) os=477;;
        3) os=352;;
        4) os=2179;;
        5) os=1743;;
        6) os=387;;
        7) os=167;;
        8) os=381;;
        9) os=391;;
        10) os=401;;
        11) os=535;;
        12) os=2076;;
        *) echo "无效的选择"; return;;
    esac

     # 显示系统配置选择菜单
    #echo "请选择系统配置: "
    #echo -e "\e[1;33m请选择机型配置: \e[0m"
    #echo -e "\e[1;33m请选择系统编号:\e[0m"
    echo -e "${GREEN}---------------------选择机型配置---------------------${NC}"
    echo -e ""
    echo "1. 1核-1G-25G磁盘-1T流量 (vc2-1c-1gb)"
    echo "2. 1核-2G-55G磁盘-2T流量 (vc2-1c-2gb)"
    echo "3. 2核-2G-65G磁盘-3T流量 (vc2-2c-2gb)"
    echo "4. 2核-4G-80G磁盘-3T流量 (vc2-2c-4gb)"
    echo -e ""
    echo -e "${GREEN}--------------------------------------------------------${NC}"
    #cho "请输入选择编号: "
    echo -e "\e[1;33m请输入选择编号: \e[0m"
    read -r plan_choice
    clear
    # 根据用户的选择设置相应的系统配置代码
    case $plan_choice in
        1) plan="vc2-1c-1gb";;
        2) plan="vc2-1c-2gb";;
        3) plan="vc2-2c-2gb";;
        4) plan="vc2-2c-4gb";;
        *) echo "无效的选择"; return;;
    esac
    # 执行vultr-cli ssh-key list命令并将输出保存到变量result中
    result=$(vultr-cli ssh-key list)

    # 使用awk命令提取ID字段，假设ID字段是第1列
    ssh_key_id=$(echo "$result" | awk 'NR==2 {print $1}')

    # 打印提取到的ID
    #echo "$ssh_key_id"
    # 创建实例
    output=$(vultr-cli instance create --region $region --plan $plan --os $os --ssh-keys $ssh_key_id --label "$label")
    #echo "实例已成功创建!"
    #echo -e "\e[1;33m实例已创建成功! \e[0m"
    if echo "$output" | grep -q "INSTANCE INFO"; then
    echo -e "\e[1;33m恭喜! 实例名称:$label已创建成功! \e[0m"
    echo -e ""
    else
        echo "$output"
fi
}


# 列出当前实例
list_instances() {
    clear
    echo -e "\e[1;33m当前运行的实例：\e[0m"
    vultr-cli instance list
    echo -e ""
    echo -e ""
}

# 删除指定的实例
delete_instance() {
    clear
    list_instances
    read -p $'\e[1;33m请输入你想要删除的实例ID（输入00取消删除操作）: \e[0m' instance_id
    if [ "$instance_id" = "00" ]; then
        echo -e "\e[1;33m取消删除操作\e[0m"
        show_menu

    else
        vultr-cli instance delete "$instance_id" > /dev/null 2>&1
        echo -e "\e[1;33m该实例已成功删除\e[0m"
    fi
}
add_instance_snapshot(){
    clear
    echo -e "\e[1;33m当前账号存在的快照：\e[0m"
    vultr-cli snapshot list
    echo -e ""
    echo -e ""
    read -p $'\e[1;33m请输入你想要新建快照的实例ID（输入00取消删除操作）: \e[0m' instance_id
    if [ "$instance_id" = "00" ]; then
        echo -e "\e[1;33m取消删除操作\e[0m"
        show_menu

    else
    clear
    read -p $'\e[1;35m输入实例名称: \e[0m' label
    # 显示地区选择菜单
#echo "请选择国家或地区"
echo -e "${GREEN}-----------------------选择国家或地区-----------------------${NC}"
echo -e ""
echo -e "\e[1;33m亚洲地区：\e[0m"
echo "1. 新加坡新加坡 (sgp)             5. 印度德里 (del)"
echo "2. 日本东京 (nrt)                 6. 印度孟买 (bom)"
echo "3. 日本大阪 (itm)                 7. 韩国首尔 (icn)"
echo "4. 印度班加罗尔 (blr)             8. 以色列特拉维夫 (tlv)"

echo -e "\e[1;33m美洲地区：\e[0m"
echo "9. 美国迈阿密 (mia)              16. 美国硅谷 (sjc)"
echo "10. 美国亚特兰大 (atl)           17. 美国新泽西州 (ewr)"
echo "11. 美国芝加哥 (ord)             18. 加拿大多伦多 (yto)"
echo "12. 美国达拉斯 (dfw)             19. 智利圣地亚哥 (scl)"
echo "13. 美国洛杉矶 (lax)             20. 巴西圣保罗 (sao)"
echo "14. 美国西雅图 (sea)             21. 墨西哥墨西哥城 (mex)"
echo "15. 美国(夏威夷)檀香山 (hnl)"

echo -e "\e[1;33m欧洲地区：\e[0m"
echo "22. 荷兰阿姆斯特丹 (ams)         26. 西班牙马德里 (mad)"
echo "23. 法国巴黎 (cdg)               27. 英国曼彻斯特 (man)"
echo "24. 德国法兰克福 (fra)           28. 波兰华沙 (waw)"
echo "25. 英国伦敦 (lhr)               29. 瑞典斯德哥尔摩 (sto)"

echo -e "\e[1;33m澳洲地区：\e[0m"
echo "30. 澳大利亚墨尔本 (mel)"
echo "31. 澳大利亚悉尼 (syd)"
echo -e "\e[1;33m非洲地区：\e[0m"
echo "32. 南非约翰内斯堡 (jnb)" | pr -t -2
echo -e ""
echo -e "${GREEN}----------------------------------------------------------${NC}"

    echo -e "\e[1;35m输入对应的数字选择国家和地区:\e[0m"
    read -r region_choice
    clear
    # 根据用户的选择设置相应的地区代码
    case $region_choice in
        1) region="sgp";;
        2) region="nrt";;
        3) region="itm";;
        4) region="blr";;
        5) region="del";;
        6) region="bom";;
        7) region="icn";;
        8) region="tlv";;
        9) region="mia";;
        10) region="atl";;
        11) region="ord";;
        12) region="dfw";;
        13) region="lax";;
        14) region="sea";;
        15) region="hnl";;
        16) region="sjc";;
        17) region="ewr";;
        18) region="yto";;
        19) region="scl";;
        20) region="sao";;
        21) region="mex";;
        22) region="ams";;     
        23) region="cdg";;
        24) region="fra";;
        25) region="lhr";;
        26) region="mad";;
        27) region="man";;
        28) region="waw";;
        29) region="sto";;
        30) region="mel";;
        31) region="syd";;   
        32) region="jnb";;

        *) echo "无效的选择"; return;;
    esac
    

     # 显示系统配置选择菜单
    #echo "请选择系统配置: "
    #echo -e "\e[1;33m请选择机型配置: \e[0m"
    #echo -e "\e[1;33m请选择系统编号:\e[0m"
    echo -e "${GREEN}---------------------选择机型配置---------------------${NC}"
    echo -e ""
    echo "1. 1核-1G-25G磁盘-1T流量 (vc2-1c-1gb)"
    echo "2. 1核-2G-55G磁盘-2T流量 (vc2-1c-2gb)"
    echo "3. 2核-2G-65G磁盘-3T流量 (vc2-2c-2gb)"
    echo "4. 2核-4G-80G磁盘-3T流量 (vc2-2c-4gb)"
    echo -e ""
    echo -e "${GREEN}--------------------------------------------------------${NC}"
    #cho "请输入选择编号: "
    echo -e "\e[1;33m请输入选择编号: \e[0m"
    read -r plan_choice
    clear
    # 根据用户的选择设置相应的系统配置代码
    case $plan_choice in
        1) plan="vc2-1c-1gb";;
        2) plan="vc2-1c-2gb";;
        3) plan="vc2-2c-2gb";;
        4) plan="vc2-2c-4gb";;
        *) echo "无效的选择"; return;;
    esac
        vultr-cli instance create --snapshot $instance_id --plan $plan --region $region  --label "$label"
        #echo $instance_id
        #echo $plan
        #echo $region
        #echo $label
        echo -e "\e[1;33m恭喜! 快照实例名称:$label已创建成功! \e[0m"
    fi
}

# 提供操作选择
show_menu() {
    while true; do
    echo -e "${GREEN}============vultr 管理脚本 ============ ${NC}"
    echo -e "${GREEN}--------------------------------------------${NC}"
        echo -e ""
        echo "1. 新建实例"
        echo "2. 列出实例"
        echo "3. 删除实例"
        echo "4. 使用快照新建实例"
        echo "0. 退出脚本"
        echo "00. 返回主菜单脚本"
        echo -e ""
    echo -e "${GREEN}--------------------------------------------${NC}"
    echo -e ""
        #read -p "请输入你的选择: " choice
        read -p $'\e[1;33m请输入你的选择: \e[0m' choice

        case $choice in
            1)
                add_instance
                ;;
            2)
                list_instances
                ;;
            3)
                delete_instance
                ;;
            4)
                add_instance_snapshot
                ;;
            0)
                exit 0
                ;;
            00)
                bash install_script.sh
                ;;    
            *)
                clear
                echo -e "\e[1;33m无效选择，请重新输入。\e[0m"
                show_menu
                break
                ;;
        esac
    done
}
# 安装或检查是否安装 Vultr CLI
install_vultr_cli
# 输入 token
input_vultr_token
# 验证 Vultr API 令牌
source ~/.bashrc
validate_vultr_token
# 显示管理菜单
show_menu
