#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error：${plain} Please run this script with root privilege \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch3xui() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    armv8 | arm64 | aarch64) echo 'arm64' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}
echo "arch: $(arch3xui)"

os_version=""
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Please use CentOS 8 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 20 ]]; then
        echo -e "${red}please use Ubuntu 20 or higher version！${plain}\n" && exit 1
    fi

elif [[ "${release}" == "fedora" ]]; then
    if [[ ${os_version} -lt 36 ]]; then
        echo -e "${red}please use Fedora 36 or higher version！${plain}\n" && exit 1
    fi

elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 10 ]]; then
        echo -e "${red} Please use Debian 10 or higher ${plain}\n" && exit 1
    fi
else
    echo -e "${red}Failed to check the OS version, please contact the author!${plain}" && exit 1
fi

install_base() {
    case "${release}" in
    centos | fedora)
        yum install -y -q wget curl tar
        ;;
    *)
        apt install -y -q wget curl tar
        ;;
    esac
}

#This function will be called when user installed z-ui out of sercurity
config_after_install() {
    echo -e "${yellow}Install/update finished! For security it's recommended to modify panel settings ${plain}"
    read -p "Do you want to continue with the modification [y/n]? ": config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        read -p "Please set up your username:" config_account
        echo -e "${yellow}Your username will be:${config_account}${plain}"
        read -p "Please set up your password:" config_password
        echo -e "${yellow}Your password will be:${config_password}${plain}"
        read -p "Please set up the panel port:" config_port
        echo -e "${yellow}Your panel port is:${config_port}${plain}"
        echo -e "${yellow}Initializing, please wait...${plain}"
        /usr/local/z-ui/z-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}Account name and password set successfully!${plain}"
        /usr/local/z-ui/z-ui setting -port ${config_port}
        echo -e "${yellow}Panel port set successfully!${plain}"
    else
        echo -e "${red}cancel...${plain}"
        if [[ ! -f "/etc/z-ui/z-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            /usr/local/z-ui/z-ui setting -username ${usernameTemp} -password ${passwordTemp}
            echo -e "this is a fresh installation,will generate random login info for security concerns:"
            echo -e "###############################################"
            echo -e "${green}username:${usernameTemp}${plain}"
            echo -e "${green}password:${passwordTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red}if you forgot your login info,you can type z-ui and then type 7 to check after installation${plain}"
        else
            echo -e "${red} this is your upgrade,will keep old settings,if you forgot your login info,you can type z-ui and then type 7 to check${plain}"
        fi
    fi
    /usr/local/z-ui/z-ui migrate
}

install_z-ui() {
    systemctl stop z-ui
    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/ozipoetra/z-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to fetch z-ui version, it maybe due to Github API restrictions, please try it later${plain}"
            exit 1
        fi
        echo -e "Got z-ui latest version: ${last_version}, beginning the installation..."
        wget -N --no-check-certificate -O /usr/local/z-ui-linux-$(arch3xui).tar.gz https://github.com/ozipoetra/z-ui/releases/download/${last_version}/z-ui-linux-$(arch3xui).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading z-ui failed, please be sure that your server can access Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/ozipoetra/z-ui/releases/download/${last_version}/z-ui-linux-$(arch3xui).tar.gz"
        echo -e "Begining to install z-ui $1"
        wget -N --no-check-certificate -O /usr/local/z-ui-linux-$(arch3xui).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download z-ui $1 failed,please check the version exists ${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/z-ui/ ]]; then
        rm /usr/local/z-ui/ -rf
    fi

    tar zxvf z-ui-linux-$(arch3xui).tar.gz
    rm z-ui-linux-$(arch3xui).tar.gz -f
    cd z-ui
    chmod +x z-ui bin/ozip-linux-$(arch3xui)
    cp -f z-ui.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/z-ui https://raw.githubusercontent.com/ozipoetra/z-ui/main/z-ui.sh
    chmod +x /usr/local/z-ui/z-ui.sh
    chmod +x /usr/bin/z-ui
    config_after_install
    #echo -e "If it is a new installation, the default web port is ${green}2053${plain}, The username and password are ${green}admin${plain} by default"
    #echo -e "Please make sure that this port is not occupied by other procedures,${yellow} And make sure that port 2053 has been released${plain}"
    #    echo -e "If you want to modify the 2053 to other ports and enter the z-ui command to modify it, you must also ensure that the port you modify is also released"
    #echo -e ""
    #echo -e "If it is updated panel, access the panel in your previous way"
    #echo -e ""
    systemctl daemon-reload
    systemctl enable z-ui
    systemctl start z-ui
    echo -e "${green}z-ui ${last_version}${plain} installation finished, it is running now..."
    echo -e ""
    echo -e "z-ui control menu usages: "
    echo -e "----------------------------------------------"
    echo -e "z-ui              - Enter     Admin menu"
    echo -e "z-ui start        - Start     z-ui"
    echo -e "z-ui stop         - Stop      z-ui"
    echo -e "z-ui restart      - Restart   z-ui"
    echo -e "z-ui status       - Show      z-ui status"
    echo -e "z-ui enable       - Enable    z-ui on system startup"
    echo -e "z-ui disable      - Disable   z-ui on system startup"
    echo -e "z-ui log          - Check     z-ui logs"
    echo -e "z-ui update       - Update    z-ui"
    echo -e "z-ui install      - Install   z-ui"
    echo -e "z-ui uninstall    - Uninstall z-ui"
    echo -e "----------------------------------------------"
}

echo -e "${green}Running...${plain}"
install_base
install_z-ui $1
