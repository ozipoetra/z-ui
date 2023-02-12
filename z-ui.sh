#!/bin/bash

export LANG=en_US.UTF-8

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora", "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove" "apk del -f")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f")

[[ $EUID -ne 0 ]] && red "Please run the script as the root user" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "Does not support the current OS, please use the a supported one" && exit 1

os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

[[ $SYSTEM == "CentOS" && ${os_version} -lt 7 ]] && echo -e "Please use the system 7 or higher!" && exit 1
[[ $SYSTEM == "Fedora" && ${os_version} -lt 29 ]] && echo -e "Please use Fedora 29 or higher!" && exit 1
[[ $SYSTEM == "Ubuntu" && ${os_version} -lt 16 ]] && echo -e "Please use Ubuntu 16 or higher!" && exit 1
[[ $SYSTEM == "Debian" && ${os_version} -lt 9 ]] && echo -e "Please use Debian 9 or higher!" && exit 1

archAffix(){
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        s390x ) echo 's390x' ;;
        * ) red "Unsupported CPU architecture!" && exit 1 ;;
    esac
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [default $2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Whether to restart the z-ui panel? It will also restart XRAY" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${YELLOW}Press Enter key and return to the main menu: ${PLAIN}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/ozipoetra/z-ui/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    read -rp "This function will update the z-ui panel to the latest version. Data will not be lost. Whether to continues? [Y/N]: " yn
    if [[ $yn =~ "Y"|"y" ]]; then
        systemctl stop z-ui
        if [[ -e /usr/local/z-ui/ ]]; then
            cd
            rm -rf /usr/local/z-ui/
        fi
        
        last_version=$(curl -Ls "https://api.github.com/repos/ozipoetra/z-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || last_version=$(curl -sm8 https://raw.githubusercontent.com/ozipoetra/z-ui/main/config/version)
        if [[ -z "$last_version" ]]; then
            red "Detecting the z-ui version failed, please make sure your server can connect to the GitHub API"
            exit 1
        fi
        
        yellow "The latest version of z-ui is: $ {last_version}, starting update..."
        wget -N --no-check-certificate -O /usr/local/z-ui.zip https://github.com/ozipoetra/z-ui/releases/download/v1.2/z-ui.zip
        if [[ $? -ne 0 ]]; then
            red "Download the z-ui failure, please make sure your server can connect and download the files from github"
            exit 1
        fi
        
        cd /usr/local/
        unzip z-ui.zip
        rm -f z-ui-linux-$(archAffix).tar.gz
        
        cd z-ui
        chmod +x z-ui bin/xray-linux-amd64
        cp -f z-ui.service /etc/systemd/system/
        
        wget -N --no-check-certificate https://raw.githubusercontent.com/ozipoetra/z-ui/main/z-ui.sh -O /usr/bin/z-ui
        chmod +x /usr/local/z-ui/z-ui.sh
        chmod +x /usr/bin/z-ui
        
        systemctl daemon-reload
        systemctl enable z-ui >/dev/null 2>&1
        systemctl start z-ui
        systemctl restart z-ui
        
        green "The update is completed, and the z-ui panel has been automatically restarted "
        exit 1
    else
        red "The upgrade z-ui panel has been canceled!"
        exit 1
    fi
}

uninstall() {
    confirm "Are you sure to uninstall the z-ui panel, it will uninstall XRAY also?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop z-ui
    systemctl disable z-ui
    rm /etc/systemd/system/z-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/z-ui/ -rf
    rm /usr/local/z-ui/ -rf
    rm /usr/bin/z-ui -f
    green "z-ui panel has been completely uninstalled. Bye Bye!"
}

reset_user() {
    confirm "Are you sure to reset the username and password of the panel?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    read -rp "Please set the login user name [default is a random user name]: " config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "Please set the login password [default is a random password]: " config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    /usr/local/z-ui/z-ui setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    echo -e "Panel login user name has been reset to: ${GREEN} ${config_account} ${PLAIN}"
    echo -e "Panel login password has been reset to: ${GREEN} ${config_password} ${PLAIN}"
    green "Please use the new login user name and password to access the z-ui panel. Also remember them!"
    confirm_restart
}

reset_config() {
    confirm "Are you sure you want to reset all settings? The account data will not be lost, the username and password will not change" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/z-ui/z-ui setting -reset >/dev/null 2>&1
    echo -e "All panel settings have been reset to the default value, please restart the panel and use the web access port $ {Green} 54321 $ {plain} "
    confirm_restart
}

set_port() {
    echo && echo -n -e "Enter the new port number[1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        red "Aborted!"
        before_show_menu
    else
        until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; do
            if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; then
                yellow "The access port you set is currently in use, please reassign another port"
                echo -n -e "Input terminal number[1-65535]: " && read port
            fi
        done
        /usr/local/z-ui/z-ui setting -port ${port} >/dev/null 2>&1
        echo -e "After the setting port is complete. Use the newly set port ${${GREEN}} ${port} ${PLAIN} to access the panel"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        green "The z-ui panel is running, no need to start again, if you need to restart the panel, please use the restart option"
    else
        systemctl start z-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            green "z-ui panel is successfully started"
        else
            red "Starting the z-ui panel keep failing, please use z-ui Log to view debug information"
        fi
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        green "The z-ui panel has already stopped, no need to stop again"
    else
        systemctl stop z-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            green "z-ui and XRAY stopped successfully"
        else
            red "Stopping the z-ui panel keeps failing, please use z-ui Log to view the debug information"
        fi
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart z-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        green "z-ui and XRAY restarted successfully"
    else
        red "Restarting the z-ui panel keeps failing, please use z-ui Log to view the debug information"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status z-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable_xui() {
    systemctl enable z-ui
    if [[ $? == 0 ]]; then
        green "z-ui will be automatically started after upon system startup"
    else
        red "Setting automatic start up keeps failing, please use z-ui Log to view the debug information"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable_xui() {
    systemctl disable z-ui
    if [[ $? == 0 ]]; then
        green "Canceled the automatic start up of z-ui upon system startup"
    else
        red "Cancelling the automatic start up of z-ui keeps failing, please use z-ui Log to view the debug information"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u z-ui.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

migrate_v2_ui() {
    /usr/local/z-ui/z-ui v2-ui
    
    before_show_menu
}

install_bbr() {
    # temporary workaround for installing bbr
    bash <(curl -L -s https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
    echo ""
    before_show_menu
}

update_shell() {
    wget -O /usr/bin/z-ui -N --no-check-certificate https://github.com/ozipoetra/z-ui/raw/main/z-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        red "Downloading the script failed, please make sure your server can connect and download the files from github"
        before_show_menu
    else
        chmod +x /usr/bin/z-ui
        green "Upgrading the script succeed, please re-run the script" && exit 1
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/z-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status z-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled z-ui)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        red "The z-ui panel has been installed, please do not repeat the installation"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        red "Please install the z-ui panel first"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "Panel state: ${GREEN}Running${PLAIN}"
            show_enable_status
        ;;
        1)
            echo -e "Panel state: ${YELLOW}Installed. But not running${PLAIN}"
            show_enable_status
        ;;
        2)
            echo -e "Panel state: ${RED}Not Installed${PLAIN}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Whether to start at your own boot: ${GREEN}Yes${PLAIN}"
    else
        echo -e "Whether to start at your own boot: ${RED}no${PLAIN}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "XRay status: ${GREEN}Running${PLAIN}"
    else
        echo -e "XRay status: ${RED}Not running${PLAIN}"
    fi
}

open_ports(){
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    green "WARNING: All network ports in the server have been opened!"
    before_show_menu
}

update_geo(){
    systemctl stop z-ui
    cd /usr/local/z-ui/bin
    rm -f geoip.dat geosite.dat
    wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
    wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
    systemctl start z-ui
    green "Geosite and Geoip have been updated successfully！"
}

check_login_info(){
    yellow "The server and the z-ui panel configurations are being checked, please wait ..."
    
    WgcfIPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    WgcfIPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $WgcfIPv4Status =~ "on"|"plus" ]] || [[ $WgcfIPv6Status =~ "on"|"plus" ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        v6=$(curl -s6m8 ip.gs -k)
        v4=$(curl -s4m8 ip.gs -k)
        wg-quick up wgcf >/dev/null 2>&1
    else
        v6=$(curl -s6m8 ip.gs -k)
        v4=$(curl -s4m8 ip.gs -k)
    fi
    
    config_port=$(/usr/local/z-ui/z-ui 2>&1 | grep tcp | awk '{print $5}' | sed "s/://g")
}

show_usage() {
    green "z-ui English v${last_version} Installation is Completed, The Panel has been Started"
    echo -e ""
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e "${GREEN}   __   __           _    _ _____    ______             _ _     _      ${PLAIN}"
    echo -e "${GREEN}   \ \ / /          | |  | |_   _|  |  ____|           | (_)   | |     ${PLAIN}"
    echo -e "${GREEN}    \ V /   ______  | |  | | | |    | |__   _ __   __ _| |_ ___| |__   ${PLAIN}"
    echo -e "${GREEN}     > <   |______| | |  | | | |    |  __| |  _ \ / _  | | / __|  _ \  ${PLAIN}"
    echo -e "${GREEN}    / . \           | |__| |_| |_   | |____| | | | (_| | | \__ \ | | | ${PLAIN}"
    echo -e "${GREEN}   /_/ \_\           \____/|_____|  |______|_| |_|\__, |_|_|___/_| |_| ${PLAIN}"
    echo -e "${GREEN}                                                  __/ |                ${PLAIN}"
    echo -e "${GREEN}                                                 |___/                 ${PLAIN}"
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e ""
    echo -e "------------------------------------------------------------------------------"
    echo -e "z-ui MANAGEMENT SCRIPT USAGE: "
    echo -e "------------------------------------------------------------------------------"
    echo -e "z-ui              - Show the management menu"
    echo -e "z-ui start        - Start z-ui panel"
    echo -e "z-ui stop         - Stop z-ui panel"
    echo -e "z-ui restart      - Restart z-ui panel"
    echo -e "z-ui status       - View z-ui status"
    echo -e "z-ui enable       - Set z-ui boot self-starting"
    echo -e "z-ui disable      - Cancel z-ui boot self-starting"
    echo -e "z-ui log          - View z-ui log"
    echo -e "z-ui v2-ui        - Migrate V2-UI to z-ui"
    echo -e "z-ui update       - Update z-ui panel"
    echo -e "z-ui install      - Install z-ui panel"
    echo -e "z-ui uninstall    - Uninstall z-ui panel"
    echo -e "------------------------------------------------------------------------------"
    echo -e ""
}

show_menu() {
    echo -e "
 -------------------------------------------------------------------------------- 
  ${GREEN}   __   __           _    _ _____    ______             _ _     _       ${PLAIN} 
  ${GREEN}   \ \ / /          | |  | |_   _|  |  ____|           | (_)   | |      ${PLAIN}
  ${GREEN}    \ V /   ______  | |  | | | |    | |__   _ __   __ _| |_ ___| |__    ${PLAIN}
  ${GREEN}     > <   |______| | |  | | | |    |  __| |  _ \ / _  | | / __|  _ \   ${PLAIN}
  ${GREEN}    / . \           | |__| |_| |_   | |____| | | | (_| | | \__ \ | | |  ${PLAIN} 
  ${GREEN}   /_/ \_\           \____/|_____|  |______|_| |_|\__, |_|_|___/_| |_|  ${PLAIN}
  ${GREEN}                                                  __/ |                 ${PLAIN}
  ${GREEN}                                                 |___/                  ${PLAIN}
--------------------------------------------------------------------------------
  ${GREEN}z-ui ENGLISH PANEL MANAGEMENT SCRIPT ${PLAIN}
--------------------------------------------------------------------------------
  ${GREEN}0.${PLAIN} Exit Script
--------------------------------------------------------------------------------
  ${GREEN}1.${PLAIN} Install z-ui
  ${GREEN}2.${PLAIN} Update z-ui
  ${GREEN}3.${PLAIN} Uninstalled z-ui
--------------------------------------------------------------------------------
  ${GREEN}4.${PLAIN} Reset Username Password
  ${GREEN}5.${PLAIN} Reset Panel Settings
  ${GREEN}6.${PLAIN} Set the Panel Web Port
--------------------------------------------------------------------------------
  ${GREEN}7.${PLAIN} Start z-ui
  ${GREEN}8.${PLAIN} Stop z-ui
  ${GREEN}9.${PLAIN} Restart z-ui
 ${GREEN}10.${PLAIN} Check z-ui Status
 ${GREEN}11.${PLAIN} View z-ui Log
---------------------------------------------------------------------------------
 ${GREEN}12.${PLAIN} Set the z-ui auto-start at boot
 ${GREEN}13.${PLAIN} Cancel the z-ui auto-start at boot
---------------------------------------------------------------------------------
 ${GREEN}14.${PLAIN} Update Geosite and Geoip
 ${GREEN}15.${PLAIN} One-click installation BBR (the latest kernel)
 ${GREEN}16.${PLAIN} One-click application certificate (ACME script application)
 ${GREEN}17.${PLAIN} Open all network ports in the server
 ${GREEN}18.${PLAIN} Install and configure Cloudflare Warp (Experimental)
 --------------------------------------------------------------------------------   "
    show_status
    echo ""
    if [[ -n $v4 && -z $v6 ]]; then
        echo -e "Panel IPv4 login address is: ${GREEN}http://$v4:$config_port ${PLAIN}"
    elif [[ -n $v6 && -z $v4 ]]; then
        echo -e "Panel IPv6 login address is: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    elif [[ -n $v4 && -n $v6 ]]; then
        echo -e "Panel IPv4 login address is: ${GREEN}http://$v4:$config_port ${PLAIN}"
        echo -e "Panel IPv6 login address is: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    fi
    echo && read -rp "Please enter the option [0-18]: " num
    
    case "${num}" in
        0) exit 1 ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && reset_user ;;
        5) check_install && reset_config ;;
        6) check_install && set_port ;;
        7) check_install && start ;;
        8) check_install && stop ;;
        9) check_install && restart ;;
        10) check_install && status ;;
        11) check_install && show_log ;;
        12) check_install && enable_xui ;;
        13) check_install && disable_xui ;;
        14) update_geo ;;
        15) install_bbr ;;
        16) wget -N --no-check-certificate https://raw.githubusercontent.com/ozipoetra/z-ui/main/acme.sh && bash acme.sh && before_show_menu ;;
        17) open_ports ;;
        18) wget -N --no-check-certificate https://raw.githubusercontent.com/taffychan/warp/main/warp.sh && bash warp.sh && before_show_menu ;;
        *) red "Please enter the correct option [0-18]" ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable_xui 0 ;;
        "disable") check_install 0 && disable_xui 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "v2-ui") check_install 0 && migrate_v2_ui 0 ;;
        "update") check_install 0 && update ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        *) show_usage ;;
    esac
else
    check_login_info && show_menu
fi
