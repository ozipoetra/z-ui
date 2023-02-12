#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

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

[[ $EUID -ne 0 ]] && red "This script must be run as root user！" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "Script doesn't support your system. Please use a supported one" && exit 1

cur_dir=$(pwd)
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

[[ $SYSTEM == "CentOS" && ${os_version} -lt 7 ]] && echo -e "Please use the system 7 or higher version of the system!" && exit 1
[[ $SYSTEM == "Fedora" && ${os_version} -lt 29 ]] && echo -e "Please use Fedora 29 or higher version system!" && exit 1
[[ $SYSTEM == "Ubuntu" && ${os_version} -lt 16 ]] && echo -e "Please use Ubuntu 16 or higher version system!" && exit 1
[[ $SYSTEM == "Debian" && ${os_version} -lt 9 ]] && echo -e "Please use Debian 9 or higher version system!" && exit 1

archAffix(){
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        s390x ) echo 's390x' ;;
        * ) red "Unsupported CPU architecture! " && rm -f install.sh && exit 1 ;;
    esac
}

info_bar(){
    clear
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
    echo ""
    echo -e "OS: ${GREEN} ${CMD} ${PLAIN}"
    echo ""
    sleep 2
}

check_status(){
    yellow "Checking the IP configuration environment of the server. Please wait..." && sleep 1
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
        if [[ -z $v4 && -n $v6 ]]; then
            yellow "IPv6 only is detected. So the DNS64 parsing server has been added automatically"
            echo -e "nameserver 2606:4700:4700::1111" > /etc/resolv.conf
        fi
    fi
    sleep 1
}

install_base(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    if [[ -z $(type -P curl) ]]; then
        ${PACKAGE_INSTALL[int]} curl
    fi
    if [[ -z $(type -P tar) ]]; then
        ${PACKAGE_INSTALL[int]} tar
    fi   
    check_status
}

download_xui(){

    
    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/ozipoetra/z-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || last_version=$(curl -sm8 https://raw.githubusercontent.com/ozipoetra/z-ui/main/config/version >/dev/null 2>&1)
        if [[ -z "$last_version" ]]; then
            red "Detecting the z-ui version failed, please make sure your server can connect to the Github API"
            rm -f install.sh
            exit 1
        fi
        yellow "The latest version of z-ui is detected: $ {last_version}, starting installation..."
        wget -N --no-check-certificate -O /usr/local/z-ui.zip https://github.com/ozipoetra/z-ui/releases/download/v1.2/z-ui.zip
        if [[ $? -ne 0 ]]; then
            red "Download the z-ui failure, please make sure your server can connect and download files from github"
            rm -f install.sh
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/ozipoetra/z-ui/releases/download/v1.2/z-ui.zip"
        yellow "Starting installation z-ui $1"
        wget -N --no-check-certificate -O /usr/local/z-ui.zip ${url}
        if [[ $? -ne 0 ]]; then
            red "Download z-ui V $ 1 Failure, please make sure this version exists"
            rm -f install.sh
            exit 1
        fi
    fi
    
    cd /usr/local/
    unzip z-ui.zip
    rm -f z-ui.zip
    
    cd z-ui
    chmod +x z-ui bin/ozip-linux-amd64
    cp -f z-ui.service /etc/systemd/system/
    
    wget -N --no-check-certificate https://raw.githubusercontent.com/ozipoetra/z-ui/main/z-ui.sh -O /usr/bin/z-ui
    chmod +x /usr/local/z-ui/z-ui.sh
    chmod +x /usr/bin/z-ui
}

panel_config() {
    yellow "For security reasons, after the installation/ update, you need to remember the port and the account password"
    read -rp "Please set the login user name [default is a random user name]: " config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "Please set the login password. Don't include spaces [default is a random password]: " config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "Please set the panel access port [default is a random port]: " config_port
    [[ -z $config_port ]] && config_port=$(shuf -i 1000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$config_port") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w  "$config_port") ]]; then
            yellow "The port you set is currently in uese, please reassign another port"
            read -rp "Please set the panel access port [default ia a random port]: " config_port
            [[ -z $config_port ]] && config_port=$(shuf -i 1000-65535 -n 1)
        fi
    done
    /usr/local/z-ui/z-ui setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    /usr/local/z-ui/z-ui setting -port ${config_port} >/dev/null 2>&1
}

install_xui() {
    info_bar
    
    if [[ -e /usr/local/z-ui/ ]]; then
        yellow "The z-ui panel has been installed at present. Please confirm you want to update it. There would not be any data loss."
        read -rp "Please enter the option [y/n, default n]: " yn
        if [[ $yn =~ "Y"|"y" ]]; then
            cd
            mv /etc/z-ui/z-ui.db /etc/z-ui.db.bak # Backing up Chinese z-ui db (if any)
            mv /etc/z-ui/z-ui.db /etc/z-ui.db.bak # Backing up English z-ui db 
            systemctl stop z-ui
            systemctl disable z-ui
            rm /etc/systemd/system/z-ui.service -f
            systemctl daemon-reload
            systemctl reset-failed 
            rm /etc/z-ui/ -rf
            rm /usr/local/z-ui/ -rf
            rm /usr/bin/z-ui -f
        else
            red "Cancelled. The script exits!"
            exit 1
        fi
    fi
    
    systemctl stop z-ui >/dev/null 2>&1
    
    install_base
    download_xui $1
    
    cd
    mkdir /etc/z-ui #makidng a directory to import the backup
    mv /etc/z-ui.db.bak /etc/z-ui/z-ui.db # Importing the backed up db
    
    panel_config
    
    systemctl daemon-reload
    systemctl enable z-ui >/dev/null 2>&1
    systemctl start z-ui 
    systemctl restart z-ui
    
    cd $cur_dir
    rm -f install.sh
    green "z-ui v${last_version} Installation / Upgrade is Completed, The Panel has been Started"
    echo -e ""
    echo -e "${GREEN} --------------------------------------------------------------------  ${PLAIN}"
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
    echo -e "------------------------------------------------------------------------------"
    echo -e "Please do consider supporting authors"
    echo -e "------------------------------------------------------------------------------"
    echo -e "vaxilu            - https://github.com/vaxilu" 
    echo -e "taffychan         - https://github.com/taffychan"  
    echo -e "Hossin Asaadi     - https://github.com/hossinasaadi"
    echo -e "Yu FranzKafka     - https://github.com/FranzKafkaYu"
    echo -e "Niduka Akalanka   - https://github.com/ozipoetra"
    echo -e "--------------------------------------------------------------------------------"
    show_login_info
    echo -e ""
    yellow "(If you cannot access the z-ui panel, first enter the z-ui command in the SSH command line, and then select the 17 option to let go of the firewall port)"
}

show_login_info(){
    if [[ -n $v4 && -z $v6 ]]; then
        echo -e "Panel IPv4 login address is: ${GREEN}http://$v4:$config_port ${PLAIN}"
    elif [[ -n $v6 && -z $v4 ]]; then
        echo -e "Panel IPv6 login address is: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    elif [[ -n $v4 && -n $v6 ]]; then
        echo -e "Panel IPv4 login address is: ${GREEN}http://$v4:$config_port ${PLAIN}"
        echo -e "Panel IPv6 login address is: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    fi
    echo -e "Username: ${GREEN}$config_account ${PLAIN}"
    echo -e "Password: ${GREEN}$config_password ${PLAIN}"
}

install_xui $1
