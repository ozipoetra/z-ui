#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

#Add some basic function here
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}
# check root
[[ $EUID -ne 0 ]] && LOGE "${red}fatal error:please run this script with root privilege${plain}\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    LOGE "check system os failed,please contact with author!\n" && exit 1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        LOGE "${red}please use CentOS 7 or higher version${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        LOGE "${red}please use Ubuntu 16 or higher version${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        LOGE "${red}please use Debian 8 or higher version${plain}\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [default:$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "confirm to restart z-ui,xray service will be restart" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}enter to return to the control menu: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/ozipoetra/z-ui/master/install_en.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "will upgrade to the latest,continue?" "n"
    if [[ $? != 0 ]]; then
        LOGE "cancelled..."
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/ozipoetra/z-ui/master/install_en.sh)
    if [[ $? == 0 ]]; then
        LOGI "upgrade finished,restart completed"
        exit 0
    fi
}

uninstall() {
    confirm "sure you want to uninstall z-ui?" "n"
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

    echo ""
    echo -e "uninstall z-ui succeed,you can delete this script by ${green}rm /usr/bin/z-ui -f${plain}"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

reset_user() {
    confirm "are you sure you want to reset the username and password to ${green}admin${plain} ?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/z-ui/z-ui setting -username admin -password admin
    echo -e "your username and password are reset to ${green}admin${plain},restart z-ui to take effect"
    confirm_restart
}

reset_config() {
    confirm "are you sure you want to reset all settings,user data will not be lost" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/z-ui/z-ui setting -reset
    echo -e "all settings are reset to default,please restart z-ui,and use default port ${green}54321${plain} to access panel"
    confirm_restart
}

check_config() {
    info=$(/usr/local/z-ui/z-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "get current settings error,please check logs"
        show_menu
    fi
    LOGI "${info}"
}

set_port() {
    echo && echo -n -e "please set a port[1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        LOGD "cancelled..."
        before_show_menu
    else
        /usr/local/z-ui/z-ui setting -port ${port}
        echo -e "set port done,please restart z-ui,and use this new port ${green}${port}${plain} to access panel"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "z-ui is running,no need to start agin"
    else
        systemctl start z-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "start z-ui  succeed"
        else
            LOGE "start z-ui failed,please check logs"
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
        LOGI "z-ui is stopped,no need to stop again"
    else
        systemctl stop z-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "stop z-ui succeed"
        else
            LOGE "stop z-ui failed,please check logs"
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
        LOGI "restart z-ui succeed"
    else
        LOGE "stop z-ui failed,please check logs"
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

enable() {
    systemctl enable z-ui
    if [[ $? == 0 ]]; then
        LOGI "enable z-ui on system startup succeed"
    else
        LOGE "enable z-ui on system startup failed"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable z-ui
    if [[ $? == 0 ]]; then
        LOGI "disable z-ui on system startup succeed"
    else
        LOGE "disable z-ui on system startup failed"
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
    wget -O /usr/bin/z-ui -N --no-check-certificate https://github.com/ozipoetra/z-ui/raw/master/z-ui_en.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "update shell script failed,please check whether your server can access github"
        before_show_menu
    else
        chmod +x /usr/bin/z-ui
        LOGI "update shell script succeed" && exit 0
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
        LOGE "z-ui is installed already"
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
        LOGE "please install z-ui first"
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
        echo -e "z-ui status: ${green}running${plain}"
        show_enable_status
        ;;
    1)
        echo -e "z-ui status: ${yellow}stopped${plain}"
        show_enable_status
        ;;
    2)
        echo -e "z-ui status: ${red}not installed${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "enable on system startup: ${green}yes${plain}"
    else
        echo -e "enable on system startup: ${red}no${plain}"
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
        echo -e "xray status: ${green}running${plain}"
    else
        echo -e "xray status: ${red}stopped${plain}"
    fi
}

#this will be an entrance for ssl cert issue
#here we can provide two different methods to issue cert
#first.standalone mode second.DNS API mode
ssl_cert_issue() {
    local method=""
    echo -E ""
    LOGD "********Usage********"
    LOGI "this shell script will use acme to help issue certs."
    LOGI "here we provide two methods for issuing certs:"
    LOGI "method 1:acme standalone mode,need to keep port:80 open"
    LOGI "method 2:acme DNS API mode,need provide Cloudflare Global API Key"
    LOGI "recommend method 2 first,if it fails,you can try method 1."
    LOGI "certs will be installed in /root/cert directory"
    read -p "please choose which method do you want,type 1 or 2": method
    LOGI "you choosed method:${method}"

    if [ "${method}" == "1" ]; then
        ssl_cert_issue_standalone
    elif [ "${method}" == "2" ]; then
        ssl_cert_issue_by_cloudflare
    else
        LOGE "invalid input,please check it..."
        exit 1
    fi
}

install_acme() {
    cd ~
    LOGI "install acme..."
    curl https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "install acme failed"
        return 1
    else
        LOGI "install acme succeed"
    fi
    return 0
}

#method for standalone mode
ssl_cert_issue_standalone() {
    #check for acme.sh first
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "acme.sh could not be found. we will install it"
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "install acme failed, please check logs"
            exit 1
        fi
    fi
    #install socat second
    if [[ x"${release}" == x"centos" ]]; then
        yum install socat -y
    else
        apt install socat -y
    fi
    if [ $? -ne 0 ]; then
        LOGE "install socat failed, please check logs"
        exit 1
    else
        LOGI "install socat succeed..."
    fi
    #creat a directory for install cert
    certPath=/root/cert
    if [ ! -d "$certPath" ]; then
        mkdir $certPath
    else
        rm -rf $certPath
        mkdir $certPath
    fi
    #get the domain here,and we need verify it
    local domain=""
    read -p "please input your domain:" domain
    LOGD "your domain is:${domain},check it..."
    #here we need to judge whether there exists cert already
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
    if [ ${currentCert} == ${domain} ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "system already have certs here,can not issue again,current certs details:"
        LOGI "$certInfo"
        exit 1
    else
        LOGI "your domain is ready for issuing cert now..."
    fi
    #get needed port here
    local WebPort=80
    read -p "please choose which port do you use,default will be 80 port:" WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "your input ${WebPort} is invalid,will use default port"
    fi
    LOGI "will use port:${WebPort} to issue certs,please make sure this port is open..."
    #NOTE:This should be handled by user
    #open the port and kill the occupied progress
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --standalone --httpport ${WebPort}
    if [ $? -ne 0 ]; then
        LOGE "issue certs failed,please check logs"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGE "issue certs succeed,installing certs..."
    fi
    #install cert
    ~/.acme.sh/acme.sh --installcert -d ${domain} --ca-file /root/cert/ca.cer \
    --cert-file /root/cert/${domain}.cer --key-file /root/cert/${domain}.key \
    --fullchain-file /root/cert/fullchain.cer

    if [ $? -ne 0 ]; then
        LOGE "install certs failed,exit"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "install certs succeed,enable auto renew..."
    fi
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "auto renew failed,certs details:"
        ls -lah cert
        chmod 755 $certPath
        exit 1
    else
        LOGI "auto renew succeed,certs details:"
        ls -lah cert
        chmod 755 $certPath
    fi

}

#method for DNS API mode
ssl_cert_issue_by_cloudflare() {
    echo -E ""
    LOGD "******Preconditions******"
    LOGI "1.need Cloudflare account associated email"
    LOGI "2.need Cloudflare Global API Key"
    LOGI "3.your domain use Cloudflare as resolver"
    confirm "I have confirmed all these info above[y/n]" "y"
    if [ $? -eq 0 ]; then
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "install acme failed,please check logs"
            exit 1
        fi
        CF_Domain=""
        CF_GlobalKey=""
        CF_AccountEmail=""
        certPath=/root/cert
        if [ ! -d "$certPath" ]; then
            mkdir $certPath
        else
            rm -rf $certPath
            mkdir $certPath
        fi
        LOGD "please input your domain:"
        read -p "Input your domain here:" CF_Domain
        LOGD "your domain is:${CF_Domain},check it..."
        #here we need to judge whether there exists cert already
        local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
        if [ ${currentCert} == ${CF_Domain} ]; then
            local certInfo=$(~/.acme.sh/acme.sh --list)
            LOGE "system already have certs here,can not issue again,current certs details:"
            LOGI "$certInfo"
            exit 1
        else
            LOGI "your domain is ready for issuing cert now..."
        fi
        LOGD "please inout your cloudflare global API key:"
        read -p "Input your key here:" CF_GlobalKey
        LOGD "your cloudflare global API key is:${CF_GlobalKey}"
        LOGD "please input your cloudflare account email:"
        read -p "Input your email here:" CF_AccountEmail
        LOGD "your cloudflare account email:${CF_AccountEmail}"
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "change the default CA to Lets'Encrypt failed,exit"
            exit 1
        fi
        export CF_Key="${CF_GlobalKey}"
        export CF_Email=${CF_AccountEmail}
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log
        if [ $? -ne 0 ]; then
            LOGE "issue cert failed,exit"
            rm -rf ~/.acme.sh/${CF_Domain}
            exit 1
        else
            LOGI "issue cert succeed,installing..."
        fi
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} --ca-file /root/cert/ca.cer \
        --cert-file /root/cert/${CF_Domain}.cer --key-file /root/cert/${CF_Domain}.key \
        --fullchain-file /root/cert/fullchain.cer
        if [ $? -ne 0 ]; then
            LOGE "install cert failed,exit"
            rm -rf ~/.acme.sh/${CF_Domain}
            exit 1
        else
            LOGI "install cert succeed,enable auto renew..."
        fi
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "enable auto renew failed,exit"
            ls -lah cert
            chmod 755 $certPath
            exit 1
        else
            LOGI "enable auto renew succeed,cert details:"
            ls -lah cert
            chmod 755 $certPath
        fi
    else
        show_menu
    fi
}

show_usage() {
    echo "z-ui control menu usages: "
    echo "------------------------------------------"
    echo -e "z-ui              - Enter control menu"
    echo -e "z-ui start        - Start z-ui "
    echo -e "z-ui stop         - Stop  z-ui "
    echo -e "z-ui restart      - Restart z-ui "
    echo -e "z-ui status       - Show z-ui status"
    echo -e "z-ui enable       - Enable z-ui on system startup"
    echo -e "z-ui disable      - Disable z-ui on system startup"
    echo -e "z-ui log          - Check z-ui logs"
    echo -e "z-ui update       - Update z-ui "
    echo -e "z-ui install      - Install z-ui "
    echo -e "z-ui uninstall    - Uninstall z-ui "
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}z-ui control menu${plain}
  ${green}0.${plain} exit
————————————————
  ${green}1.${plain} install   z-ui
  ${green}2.${plain} update    z-ui
  ${green}3.${plain} uninstall z-ui
————————————————
  ${green}4.${plain} reset username
  ${green}5.${plain} reset panel
  ${green}6.${plain} reset panel port
  ${green}7.${plain} check panel info
————————————————
  ${green}8.${plain} start z-ui
  ${green}9.${plain} stop  z-ui
  ${green}10.${plain} restart z-ui
  ${green}11.${plain} check z-ui status
  ${green}12.${plain} check z-ui logs
————————————————
  ${green}13.${plain} enable  z-ui on system startup
  ${green}14.${plain} disable z-ui on system startup
————————————————
  ${green}15.${plain} enable bbr 
  ${green}16.${plain} issuse certs
 "
    show_status
    echo && read -p "please input a legal number[0-16],input 7 for checking login info:" num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && uninstall
        ;;
    4)
        check_install && reset_user
        ;;
    5)
        check_install && reset_config
        ;;
    6)
        check_install && set_port
        ;;
    7)
        check_install && check_config
        ;;
    8)
        check_install && start
        ;;
    9)
        check_install && stop
        ;;
    10)
        check_install && restart
        ;;
    11)
        check_install && status
        ;;
    12)
        check_install && show_log
        ;;
    13)
        check_install && enable
        ;;
    14)
        check_install && disable
        ;;
    15)
        install_bbr
        ;;
    16)
        ssl_cert_issue
        ;;
    *)
        LOGE "please input a legal number[0-16],input 7 for checking login info"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "log")
        check_install 0 && show_log 0
        ;;
    "v2-ui")
        check_install 0 && migrate_v2_ui 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
