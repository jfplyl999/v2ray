#!/bin/bash

#====================================================
#	System Request:Debian 9+/Ubuntu 18.04+/Centos 7+
#	Author:	wulabing
#	Dscription: V2ray ws+tls onekey Management
#	Version: 1.0
#	email:admin@wulabing.com
#	Official document: www.v2ray.com
#====================================================

#fonts color
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

# 版本
shell_version="1.0"
shell_mode="None"
version_cmp="/tmp/version_cmp.tmp"
v2ray_conf_dir="/etc/v2ray"
nginx_conf_dir="/etc/nginx/conf/conf.d"
v2ray_conf="${v2ray_conf_dir}/config.json"
kcptun_server_conf="/root/kcptun_server.json"
kcptun_client_conf="/root/kcptun_client.json"
kcpclientrestart="/root/kcpclientrestart.sh"
kcpserverrestart="/root/kcpserverrestart.sh"
nginx_conf="${nginx_conf_dir}/v2ray.conf"
nginx_dir="/etc/nginx"
web_dir="/home/wwwroot"
nginx_openssl_src="/usr/local/src"
v2ray_bin_file="/usr/bin/v2ray"
v2ray_info_file="$HOME/v2ray_info.inf"
v2ray_qr_config_file="/etc/v2ray/vmess_qr.json"
nginx_systemd_file="/etc/systemd/system/nginx.service"
v2ray_systemd_file="/etc/systemd/system/v2ray.service"
v2ray_access_log="/var/log/v2ray/access.log"
v2ray_error_log="/var/log/v2ray/error.log"
amce_sh_file="/root/.acme.sh/acme.sh"
nginx_version="1.16.1"
openssl_version="1.1.1d"

#生成伪装路径
camouflage=`cat /dev/urandom | head -n 10 | md5sum | head -c 8`

source /etc/os-release

#从VERSION中提取发行版系统的英文名称，为了在debian/ubuntu下添加相对应的Nginx apt源
VERSION=`echo ${VERSION} | awk -F "[()]" '{print $2}'`

check_system(){
    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]];then
        echo -e "${OK} ${GreenBG} 当前系统为 Centos ${VERSION_ID} ${VERSION} ${Font}"
        INS="yum"
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]];then
        echo -e "${OK} ${GreenBG} 当前系统为 Debian ${VERSION_ID} ${VERSION} ${Font}"
        INS="apt"
        $INS update
        ## 添加 Nginx apt源
    elif [[ "${ID}" == "ubuntu" && `echo "${VERSION_ID}" | cut -d '.' -f1` -ge 16 ]];then
        echo -e "${OK} ${GreenBG} 当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME} ${Font}"
        INS="apt"
        $INS update
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        exit 1
    fi

    $INS install dbus
    systemctl stop firewalld && systemctl disable firewalld
    echo -e "${OK} ${GreenBG} firewalld 已关闭 ${Font}"
}

is_root(){
    if [ `id -u` == 0 ]
        then echo -e "${OK} ${GreenBG} 当前用户是root用户，进入安装流程 ${Font}"
        sleep 3
    else
        echo -e "${Error} ${RedBG} 当前用户不是root用户，请切换到root用户后重新执行脚本 ${Font}"
        exit 1
    fi
}
judge(){
    if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}
chrony_install(){
    ${INS} -y install chrony
    judge "安装 chrony 时间同步服务 "

    timedatectl set-ntp true

    if [[ "${ID}" == "centos" ]];then
       systemctl enable chronyd && systemctl restart chronyd
    else
       systemctl enable chrony && systemctl restart chrony
    fi

    judge "chronyd 启动 "

    timedatectl set-timezone Asia/Shanghai

    echo -e "${OK} ${GreenBG} 等待时间同步 ${Font}"
    sleep 10

    chronyc sourcestats -v
    chronyc tracking -v
    date
    read -p "请确认时间是否准确,误差范围±3分钟(Y/N): " chrony_install
    [[ -z ${chrony_install} ]] && chrony_install="Y"
    case $chrony_install in
        [yY][eE][sS]|[yY])
            echo -e "${GreenBG} 继续安装 ${Font}"
            sleep 2
            ;;
        *)
            echo -e "${RedBG} 安装终止 ${Font}"
            exit 2
            ;;
    esac
}

dependency_install(){
    ${INS} install wget -N --no-check-certificate git lsof -y

    if [[ "${ID}" == "centos" ]];then
       ${INS} -y install crontabs
    else
       ${INS} -y install cron
    fi
    judge "安装 crontab"

    if [[ "${ID}" == "centos" ]];then
       touch /var/spool/cron/root && chmod 600 /var/spool/cron/root
       systemctl start crond && systemctl enable crond
    else
       touch /var/spool/cron/crontabs/root && chmod 600 /var/spool/cron/crontabs/root
       systemctl start cron && systemctl enable cron

    fi
    judge "crontab 自启动配置 "



    ${INS} -y install bc
    judge "安装 bc"

    ${INS} -y install unzip
    judge "安装 unzip"

    ${INS} -y install qrencode
    judge "安装 qrencode"

    if [[ "${ID}" == "centos" ]];then
       ${INS} -y groupinstall "Development tools"
    else
       ${INS} -y install build-essential
    fi
    judge "编译工具包 安装"

    if [[ "${ID}" == "centos" ]];then
       ${INS} -y install pcre pcre-devel zlib-devel epel-release
    else
       ${INS} -y install libpcre3 libpcre3-dev zlib1g-dev dbus
    fi

    ${INS} -y install rng-tools
#    judge "rng-tools 安装"

    ${INS} -y install haveged
#    judge "haveged 安装"

    sed -i -r '/^HRNGDEVICE/d;/#HRNGDEVICE=\/dev\/null/a HRNGDEVICE=/dev/urandom' /etc/default/rng-tools

    if [[ "${ID}" == "centos" ]];then
       systemctl start rngd && systemctl enable rngd
#       judge "rng-tools 启动"
       systemctl start haveged && systemctl enable haveged
#       judge "haveged 启动"
    else
       systemctl start rng-tools && systemctl enable rng-tools
#       judge "rng-tools 启动"
       systemctl start haveged && systemctl enable haveged
#       judge "haveged 启动"
    fi
}
basic_optimization(){
    # 最大文件打开数
    sed -i '/^\*\ *soft\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    sed -i '/^\*\ *hard\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    echo '* soft nofile 65536' >> /etc/security/limits.conf
    echo '* hard nofile 65536' >> /etc/security/limits.conf

    # 关闭 Selinux
    if [[ "${ID}" == "centos" ]];then
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        setenforce 0
    fi

}
port_alterid_set(){
    read -p "请输入连接端口(禁用8088\9090）（default:443）:" port
    [[ -z ${port} ]] && port="443"
    read -p "请输入alterID（default:2 仅允许填数字）:" alterID
    [[ -z ${alterID} ]] && alterID="2"
}
Set_IP_pf(){
	echo "请输入服务器的 IP :"
	read -e -p "(默认取消):" bk_ip_pf
	[[ -z "${bk_ip_pf}" ]] && echo "已取消..." && exit 1
	echo && echo "========================"
	echo -e "	服务器IP : ${GreenBG} ${bk_ip_pf} ${Font}"
	echo "========================" && echo
	
	#修改kcpclientrestart.sh
	wget -N --no-check-certificate https://raw.githubusercontent.com/jfplyl999/v2ray/master/kcpclientrestart.sh -O kcpclientrestart.sh
	chmod -x kcpclientrestart.sh
	sed -i "s/255.255.255.255/${bk_ip_pf}/g" ${kcpclientrestart}
	
	#复制kcpclientrestart.sh到开机自启文件夹
	rm -f /etc/rc2.d/S90kcpclientrestart.sh
	rm -f /etc/init.d/kcpclientrestart.sh
	cp kcpclientrestart.sh /etc/init.d/kcpclientrestart.sh
	sleep 1
	cp kcpclientrestart.sh /etc/rc2.d/S90kcpclientrestart.sh
	sleep 2
	cd /etc/rc2.d
	chmod +x S90kcpclientrestart.sh
	cd /root
	
}
changehosts(){
#修改github的hosts
cd /etc
sed -i '5a140.82.114.3    github.com' hosts
sed -i '6a192.30.253.113  github.com' hosts
sed -i '7a199.232.5.194  github.global.ssl.fastly.net' hosts
sed -i '8a199.232.28.133  raw.githubusercontent.com' hosts
}
kcptun_port_alterid_set(){
    read -p "请输入kcp与v2ray连接端口(禁用8088\9090）（default:47400）:" port
    [[ -z ${port} ]] && port="47400"
}
modify_path(){
    sed -i "/\"path\"/c \\\t  \"path\":\"\/${camouflage}\/\"" ${v2ray_conf}
    judge "V2ray 伪装路径 修改"
}
modify_alterid(){
    sed -i "/\"alterId\"/c \\\t  \"alterId\":${alterID}" ${v2ray_conf}
    judge "V2ray alterid 修改"
    [ -f ${v2ray_qr_config_file} ] && sed -i "/\"aid\"/c \\  \"aid\": \"${alterID}\"," ${v2ray_qr_config_file}
    echo -e "${GreenBG} alterID:${alterID} ${Font}"
}
modify_inbound_port(){
    if [[ "$shell_mode" != "h2" ]]
    then
        let PORT=$RANDOM+10000
        sed -i "/\"port\"/c  \    \"port\":${PORT}," ${v2ray_conf}
    else
        sed -i "/\"port\"/c  \    \"port\":${port}," ${v2ray_conf}
    fi
    judge "V2ray inbound_port 修改"
}
modify_kcptun_port(){
        #修改kcp与v2ray连接端口
		wget -N --no-check-certificate https://raw.githubusercontent.com/jfplyl999/v2ray/master/kcptun_server.json -O kcptun_server.json
		sed -i "s/47400/${port}/g" ${kcptun_server_conf}
    judge "kcp服务器监听端口 修改"
}
modify_kcptun_port_client(){
        #修改kcp与v2ray连接端口
		wget -N --no-check-certificate https://raw.githubusercontent.com/jfplyl999/v2ray/master/kcptun_client.json -O kcptun_client.json
		sed -i "s/14777/${port}/g" ${kcptun_client_conf}
    judge "kcp客户端监听端口 修改"
}
modify_UUID(){
    [ -z $UUID ] && UUID=$(cat /proc/sys/kernel/random/uuid)
    sed -i "/\"id\"/c \\\t  \"id\":\"${UUID}\"," ${v2ray_conf}
    judge "V2ray UUID 修改"
    [ -f ${v2ray_qr_config_file} ] && sed -i "/\"id\"/c \\  \"id\": \"${UUID}\"," ${v2ray_qr_config_file}
    echo -e "${GreenBG} UUID:${UUID} ${Font}"
}
modify_nginx_port(){
    sed -i "/ssl http2;$/c \\\tlisten ${port} ssl http2;" ${nginx_conf}
    judge "V2ray port 修改"
    [ -f ${v2ray_qr_config_file} ] && sed -i "/\"port\"/c \\  \"port\": \"${port}\"," ${v2ray_qr_config_file}
    echo -e "${GreenBG} 端口号:${port} ${Font}"
}
modify_nginx_other(){
    sed -i "/server_name/c \\\tserver_name ${domain};" ${nginx_conf}
    sed -i "/location/c \\\tlocation \/${camouflage}\/" ${nginx_conf}
    sed -i "/proxy_pass/c \\\tproxy_pass http://127.0.0.1:${PORT};" ${nginx_conf}
    sed -i "/return/c \\\treturn 301 https://${domain}\$request_uri;" ${nginx_conf}
    #sed -i "27i \\\tproxy_intercept_errors on;"  ${nginx_dir}/conf/nginx.conf
}
modify_nginx_other_1(){
    sed -i "/server_name/c \\\tserver_name ${domain};" ${nginx_conf}
    sed -i "/location/c \\\tlocation \/${camouflage}\/" ${nginx_conf}
    sed -i "/proxy_pass/c \\\tproxy_pass http://127.0.0.1:443;" ${nginx_conf}
    sed -i "/return/c \\\treturn 301 https://${domain}\$request_uri;" ${nginx_conf}
    #sed -i "27i \\\tproxy_intercept_errors on;"  ${nginx_dir}/conf/nginx.conf
}
web_camouflage(){
    ##请注意 这里和LNMP脚本的默认路径冲突，千万不要在安装了LNMP的环境下使用本脚本，否则后果自负
    rm -rf /home/wwwroot && mkdir -p /home/wwwroot && cd /home/wwwroot
    git clone https://github.com/wulabing/3DCEList.git
    judge "web 站点伪装"
}
v2ray_install(){
    if [[ -d /root/v2ray ]];then
        rm -rf /root/v2ray
    fi
    if [[ -d /etc/v2ray ]];then
        rm -rf /etc/v2ray
    fi
    mkdir -p /root/v2ray && cd /root/v2ray
    wget -N --no-check-certificate https://install.direct/go.sh

    ## wget -N --no-check-certificate http://install.direct/go.sh

    if [[ -f go.sh ]];then
        bash go.sh --force
        judge "安装 V2ray"
    else
        echo -e "${Error} ${RedBG} V2ray 安装文件下载失败，请检查下载地址是否可用 ${Font}"
        exit 4
    fi
    # 清除临时文件
    rm -rf /root/v2ray
}
nginx_exist_check(){
    if [[ -f "/etc/nginx/sbin/nginx" ]];then
        echo -e "${OK} ${GreenBG} Nginx已存在，跳过编译安装过程 ${Font}"
        sleep 2
    else
        nginx_install
    fi
}
udp2raw_amd64_check(){
    if [[ -f "/root/udp2raw_amd64" ]];then
        echo -e "${OK} ${GreenBG} udp2raw_amd64已存在，跳过编译安装过程 ${Font}"
        sleep 2
    else
        wget -N --no-check-certificate https://github.com/jfplyl999/v2ray/raw/master/udp2raw_amd64 -O udp2raw_amd64
		chmod +x udp2raw_amd64 
    fi
}
client_linux_amd64_check(){
    if [[ -f "/root/client_linux_amd64" ]];then
        echo -e "${OK} ${GreenBG} client_linux_amd64已存在，跳过编译安装过程 ${Font}"
        sleep 2
    else
    wget -N --no-check-certificate https://github.com/jfplyl999/v2ray/raw/master/client_linux_amd64 -O client_linux_amd64 && chmod +x client_linux_amd64 
    fi
}
server_linux_amd64_check(){
    if [[ -f "/root/server_linux_amd64" ]];then
        echo -e "${OK} ${GreenBG} server_linux_amd64已存在，跳过编译安装过程 ${Font}"
        sleep 2
    else
    wget -N --no-check-certificate https://github.com/jfplyl999/v2ray/raw/master/server_linux_amd64 -O server_linux_amd64 && chmod +x server_linux_amd64 
    fi
}

docker_exist_check(){
    if [[ -f "/var/lib/docker" ]];then
        echo -e "${OK} ${GreenBG} docker已存在，跳过编译安装过程 ${Font}"
        sleep 2
    else
        nginx_install
    fi
}
docker_install_1(){
    curl -sSL https://get.docker.com | sh
    service docker start "${OK} ${GreenBG} docker启动完成 ${Font}"
	systemctl enable docker "${OK} ${GreenBG} docker设置自启 ${Font}"
}
docker_install_2(){
    curl -sSL https://get.daocloud.io/docker | sh
	service docker start "${OK} ${GreenBG} docker启动完成 ${Font}"
	systemctl enable docker "${OK} ${GreenBG} docker设置自启 ${Font}"
}
nginx_install(){
#    if [[ -d "/etc/nginx" ]];then
#        rm -rf /etc/nginx
#    fi

    wget -N --no-check-certificate  http://nginx.org/download/nginx-${nginx_version}.tar.gz -P ${nginx_openssl_src}
    judge "Nginx 下载"
    wget -N --no-check-certificate  https://www.openssl.org/source/openssl-${openssl_version}.tar.gz -P ${nginx_openssl_src}
    judge "openssl 下载"

    cd ${nginx_openssl_src}

    [[ -d nginx-"$nginx_version" ]] && rm -rf nginx-"$nginx_version"
    tar -zxvf nginx-"$nginx_version".tar.gz

    [[ -d openssl-"$openssl_version" ]] && rm -rf openssl-"$openssl_version"
    tar -zxvf openssl-"$openssl_version".tar.gz

    [[ -d "$nginx_dir" ]] && rm -rf ${nginx_dir}

    echo -e "${OK} ${GreenBG} 即将开始编译安装 Nginx, 过程稍久，请耐心等待 ${Font}"
    sleep 4

    cd nginx-${nginx_version}
    ./configure --prefix="${nginx_dir}"                         \
            --with-http_ssl_module                              \
            --with-http_gzip_static_module                      \
            --with-http_stub_status_module                      \
            --with-pcre                                         \
            --with-http_realip_module                           \
            --with-http_flv_module                              \
            --with-http_mp4_module                              \
            --with-http_secure_link_module                      \
            --with-http_v2_module                               \
            --with-openssl=../openssl-"$openssl_version"
    judge "编译检查"
    make && make install
    judge "Nginx 编译安装"

    # 修改基本配置
    sed -i 's/#user  nobody;/user  root;/' ${nginx_dir}/conf/nginx.conf
    sed -i 's/worker_processes  1;/worker_processes  3;/' ${nginx_dir}/conf/nginx.conf
    sed -i 's/    worker_connections  1024;/    worker_connections  4096;/' ${nginx_dir}/conf/nginx.conf
    sed -i '$i include conf.d/*.conf;' ${nginx_dir}/conf/nginx.conf



    # 删除临时文件
    rm -rf nginx-"${nginx_version}"
    rm -rf openssl-"${openssl_version}"
    rm -rf ../nginx-"${nginx_version}".tar.gz
    rm -rf ../openssl-"${openssl_version}".tar.gz

    # 添加配置文件夹，适配旧版脚本
    mkdir ${nginx_dir}/conf/conf.d
}
finalspeed_server_install(){
    #服务端下载安装finalspeed
	wget -N --no-check-certificate https://raw.githubusercontent.com/jfplyl999/v2ray/master/install_fs.sh -O install_fs.sh
	chmod +x install_fs.sh
	bash install_fs.sh

	#启用finalspeed并锁定运行（默认监听端口8089，自己端口150）
	nohup ./run.sh ./udp2raw_amd64 -s -l0.0.0.0:8089 -r 127.0.0.1:150 --raw-mode faketcp --cipher-mode none -a -k "atrandys" >udp2raw.log 2>&1 &
}
udp2raw_server_install(){
    #服务端下载udp2raw和防进程停止脚本并授权
	wget -N --no-check-certificate https://raw.githubusercontent.com/jfplyl999/v2ray/master/run.sh -O run.sh
	wget -N --no-check-certificate https://raw.githubusercontent.com/jfplyl999/v2ray/master/kcpserverrestart.sh -O kcpserverrestart.sh
	chmod +x run.sh kcpserverrestart.sh
	
	#复制kcpserverrestart.sh到开机自启文件夹
	cp kcpserverrestart.sh /etc/rc2.d/S90kcpserverrestart.sh
	cd /etc/rc2.d
	chmod +x S90kcpserverrestart.sh
	cd /root
	
	#启用udp2raw并锁定运行（默认监听端口8088，与kuptun连接端口9090）
	nohup ./run.sh ./udp2raw_amd64 -s -l0.0.0.0:8088 -r 127.0.0.1:9090 --raw-mode faketcp --cipher-mode none -a -k "atrandys" >udp2raw.log 2>&1 &
}
udp2raw_client_install(){
    #客户端下载udp2raw和防进程停止脚本并授权 
	wget -N --no-check-certificate https://raw.githubusercontent.com/jfplyl999/v2ray/master/run.sh -O run.sh 
	chmod +x run.sh
	
	#启用udp2raw并锁定运行（默认监听端口8088，与kuptun连接端口9090）
	Set_IP_pf
	sleep 1
	nohup ./run.sh ./udp2raw_amd64 -c -r ${bk_ip_pf}:8088 -l0.0.0.0:9090 --raw-mode faketcp --cipher-mode none -a -k "atrandys" >udp2raw.log 2>&1 &
	
	#复制kcpclientrestart.sh到开机自启文件夹
	cp kcpclientrestart.sh /etc/rc2.d/S90kcpclientrestart.sh
	cd /etc/rc2.d
	chmod +x S90kcpclientrestart.sh
	cd /root
}
kcptun_server_install(){
 
    
	#配置kcp（与udp2raw连接端口9090，默认与v2ray连接端口47400可根据实际v2ray开通端口修改kcptun_server.json）
    wget -N --no-check-certificate https://raw.githubusercontent.com/jfplyl999/v2ray/master/kcptun_server.json -O kcptun_server.json
    
	#输入端口
	kcptun_port_alterid_set
	modify_kcptun_port
	
	#启用kcptun并锁定运行
    nohup ./run.sh ./server_linux_amd64 -c ./kcptun_server.json >kcptun.log 2>&1 &
	sleep 5
	ps -ef|grep kcptun && ps -ef|grep udp2raw
}
kcptun_client_install(){
 
	#配置kcp（与udp2raw连接端口9090，默认与v2ray连接端口14777可根据实际v2ray开通端口修改kcptun_client.json）
    wget -N --no-check-certificate https://raw.githubusercontent.com/jfplyl999/v2ray/master/kcptun_client.json -O kcptun_client.json
    
	#输入端口
	kcptun_port_alterid_set
	modify_kcptun_port_client
	
	#启用kcptun并锁定运行
    nohup ./run.sh ./client_linux_amd64 -c ./kcptun_client.json >kcptun.log 2>&1 &
	sleep 5
	ps -ef|grep kcptun && ps -ef|grep udp2raw
}
kcptun_udp2raw_restart(){
    ps -ef|grep kcptun|grep -v grep|cut -c 9-15|xargs kill -9
    ps -ef|grep udp2raw|grep -v grep|cut -c 9-15|xargs kill -9
    sleep 3
    nohup ./run.sh ./udp2raw_amd64 -s -l0.0.0.0:8088 -r 127.0.0.1:9090 --raw-mode faketcp --cipher-mode none -a -k "atrandys" >udp2raw.log 2>&1 &
    nohup ./run.sh ./server_linux_amd64 -c ./kcptun_server.json >kcptun.log 2>&1 &
    sleep 3
    ps -ef|grep kcptun && ps -ef|grep udp2raw
}
finalspeed_udp2raw_restart(){
    ps -ef|grep kcptun|grep -v grep|cut -c 9-15|xargs kill -9
    ps -ef|grep udp2raw|grep -v grep|cut -c 9-15|xargs kill -9
    sleep 3
	/etc/init.d/finalspeed start
    nohup ./run.sh ./udp2raw_amd64 -s -l0.0.0.0:8089 -r 127.0.0.1:150 --raw-mode faketcp --cipher-mode none -a -k "atrandys" >udp2raw.log 2>&1 &
    sleep 3
    ps -ef|grep kcptun && ps -ef|grep udp2raw
}
kcptun_udp2raw_client_restart(){
    ps -ef|grep kcptun|grep -v grep|cut -c 9-15|xargs kill -9
    ps -ef|grep udp2raw|grep -v grep|cut -c 9-15|xargs kill -9
    sleep 3
	
    nohup ./run.sh ./udp2raw_amd64 -c -r ${bk_ip_pf}:8089 -l0.0.0.0:9090 --raw-mode faketcp --cipher-mode none -a -k "atrandys" >udp2raw.log 2>&1 &
    nohup ./run.sh ./client_linux_amd64 -c ./kcptun_client.json >kcptun.log 2>&1 &
    sleep 3
    ps -ef|grep kcptun && ps -ef|grep udp2raw
}
finalspeed_udp2raw_client_restart(){
    	echo "请输入服务器的 IP :"
	read -e -p "(默认取消):" bk_ip_pf
	[[ -z "${bk_ip_pf}" ]] && echo "已取消..." && exit 1
	echo && echo "========================"
	echo -e "	服务器IP : ${GreenBG} ${bk_ip_pf} ${Font}"
	echo "========================" && echo
	
    ps -ef|grep kcptun|grep -v grep|cut -c 9-15|xargs kill -9
    ps -ef|grep udp2raw|grep -v grep|cut -c 9-15|xargs kill -9
    sleep 3
	nohup ./run.sh ./udp2raw_amd64 -c -r ${bk_ip_pf}:8089 -l0.0.0.0:150 --raw-mode faketcp --cipher-mode none -a -k "atrandys" >udp2raw.log 2>&1 &
    sleep 3
    ps -ef|grep kcptun && ps -ef|grep udp2raw
}
ssl_install(){
    if [[ "${ID}" == "centos" ]];then
        ${INS} install socat nc -y
    else
        ${INS} install socat netcat -y
    fi
    judge "安装 SSL 证书生成脚本依赖"

    curl  https://get.acme.sh | sh
    judge "安装 SSL 证书生成脚本"
}
domain_check(){
    read -p "请输入你的域名信息(eg:www.wulabing.com):" domain
    domain_ip=`ping ${domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    echo -e "${OK} ${GreenBG} 正在获取 公网ip 信息，请耐心等待 ${Font}"
    local_ip=`curl -4 ip.sb`
    echo -e "域名dns解析IP：${domain_ip}"
    echo -e "本机IP: ${local_ip}"
    sleep 2
    if [[ $(echo ${local_ip}|tr '.' '+'|bc) -eq $(echo ${domain_ip}|tr '.' '+'|bc) ]];then
        echo -e "${OK} ${GreenBG} 域名dns解析IP 与 本机IP 匹配 ${Font}"
        sleep 2
    else
        echo -e "${Error} ${RedBG} 请确保域名添加了正确的 A 记录，否则将无法正常使用 V2ray"
        echo -e "${Error} ${RedBG} 域名dns解析IP 与 本机IP 不匹配 是否继续安装？（y/n）${Font}" && read install
        case $install in
        [yY][eE][sS]|[yY])
            echo -e "${GreenBG} 继续安装 ${Font}"
            sleep 2
            ;;
        *)
            echo -e "${RedBG} 安装终止 ${Font}"
            exit 2
            ;;
        esac
    fi
}

port_exist_check(){
    if [[ 0 -eq `lsof -i:"$1" | grep -i "listen" | wc -l` ]];then
        echo -e "${OK} ${GreenBG} $1 端口未被占用 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} 检测到 $1 端口被占用，以下为 $1 端口占用信息 ${Font}"
        lsof -i:"$1"
        set -e
    fi
}
acme(){
    ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --force --test
    if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} SSL 证书测试签发成功，开始正式签发 ${Font}"
        sleep 2
    else
        echo -e "${Error} ${RedBG} SSL 证书测试签发失败 ${Font}"
        exit 1
    fi

    ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --force
    if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} SSL 证书生成成功 ${Font}"
        sleep 2
        mkdir /data
        ~/.acme.sh/acme.sh --installcert -d ${domain} --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc
        if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} 证书配置成功 ${Font}"
        sleep 2
        fi
    else
        echo -e "${Error} ${RedBG} SSL 证书生成失败 ${Font}"
        exit 1
    fi
}
v2ray_conf_add_tls(){
    cd /etc/v2ray
    wget -N --no-check-certificate https://raw.githubusercontent.com/wulabing/V2Ray_ws-tls_bash_onekey/master/tls/config.json -O config.json
    modify_path
    modify_alterid
    modify_inbound_port
    modify_UUID
}
v2ray_conf_add_h2(){
    cd /etc/v2ray
    wget -N --no-check-certificate https://raw.githubusercontent.com/wulabing/V2Ray_ws-tls_bash_onekey/master/http2/config.json -O config.json
    modify_path
    modify_alterid
    modify_inbound_port
    modify_UUID
}
nginx_conf_add(){
    touch ${nginx_conf_dir}/v2ray.conf
    cat>${nginx_conf_dir}/v2ray.conf<<EOF
    server {
        listen 443 ssl http2;
        ssl_certificate       /data/v2ray.crt;
        ssl_certificate_key   /data/v2ray.key;
        ssl_protocols         TLSv1.2 TLSv1.3;
        ssl_ciphers           TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
        server_name           serveraddr.com;
        index index.html index.htm;
        root  /home/wwwroot/3DCEList;
        error_page 400 = /400.html;
        location /ray/
        {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        }
}
    server {
        listen 80;
        server_name serveraddr.com;
        return 301 https://use.shadowsocksr.win\$request_uri;
    }
EOF

modify_nginx_port
modify_nginx_other
judge "Nginx 配置修改"

}
nginx_conf_add_2(){
    touch ${nginx_conf_dir}/v2ray.conf
    cat>${nginx_conf_dir}/v2ray.conf<<EOF
    server {
        listen 443 ssl http2;
        ssl_certificate       /data/v2ray.crt;
        ssl_certificate_key   /data/v2ray.key;
        ssl_protocols         TLSv1.2 TLSv1.3;
        ssl_ciphers           TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
        server_name           serveraddr.com;
        index index.html index.htm;
        root  /home/wwwroot/3DCEList;
        error_page 400 = /400.html;
        location /ray/
        {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        }
}
    server {
        listen 80;
        server_name serveraddr.com;
        return 301 https://use.shadowsocksr.win\$request_uri;
    }
EOF

modify_nginx_other_1
judge "Nginx 配置修改"

}

start_process_systemd(){
    systemctl daemon-reload
    if [[ "$shell_mode" != "h2" ]]
    then
        systemctl restart nginx
        judge "Nginx 启动"
    fi
    systemctl restart v2ray && systemctl restart nginx
    judge "V2ray 启动"
}

enable_process_systemd(){
    systemctl enable v2ray
    judge "设置 v2ray 开机自启"
    if [[ "$shell_mode" != "h2" ]]
    then
        systemctl enable nginx
        judge "设置 Nginx 开机自启"
    fi

}
start_enable_nginx(){
    systemctl restart nginx
    systemctl enable nginx
        judge "设置 Nginx v2ary 开机自启"
}
stop_process_systemd(){
    if [[ "$shell_mode" != "h2" ]]
    then
        systemctl stop nginx
    fi
    systemctl stop v2ray
}
nginx_process_disabled(){
    [ -f $nginx_systemd_file ] && systemctl stop nginx && systemctl disable nginx
}

#debian 系 9 10 适配
#rc_local_initialization(){
#    if [[ -f /etc/rc.local ]];then
#        chmod +x /etc/rc.local
#    else
#        touch /etc/rc.local && chmod +x /etc/rc.local
#        echo "#!/bin/bash" >> /etc/rc.local
#        systemctl start rc-local
#    fi
#
#    judge "rc.local 配置"
#}
acme_cron_update(){
    if [[ "${ID}" == "centos" ]];then
        sed -i "/acme.sh/c 0 3 * * 0 systemctl stop nginx && \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" \
        > /dev/null && systemctl start nginx" /var/spool/cron/root
    else
        sed -i "/acme.sh/c 0 3 * * 0 systemctl stop nginx && \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" \
        > /dev/null && systemctl start nginx" /var/spool/cron/crontabs/root
    fi
    judge "cron 计划任务更新"
}

vmess_qr_config_tls_ws(){
    cat > $v2ray_qr_config_file <<-EOF
{
  "v": "2",
  "ps": "wulabing_${domain}",
  "add": "${domain}",
  "port": "${port}",
  "id": "${UUID}",
  "aid": "${alterID}",
  "net": "ws",
  "type": "none",
  "host": "${domain}",
  "path": "/${camouflage}/",
  "tls": "tls"
}
EOF
}

vmess_qr_config_h2(){
    cat > $v2ray_qr_config_file <<-EOF
{
  "v": "2",
  "ps": "wulabing_${domain}",
  "add": "${domain}",
  "port": "${port}",
  "id": "${UUID}",
  "aid": "${alterID}",
  "net": "h2",
  "type": "none",
  "path": "/${camouflage}/",
  "tls": "tls"
}
EOF
}

vmess_qr_link_image(){
    vmess_link="vmess://$(cat $v2ray_qr_config_file | base64 -w 0)"
    echo -e "${Red} URL导入链接:${vmess_link} ${Font}" >> ${v2ray_info_file}
    echo -e "${Red} 二维码: ${Font}" >> ${v2ray_info_file}
    echo -n "${vmess_link}"| qrencode -o - -t utf8 >> ${v2ray_info_file}
}

info_extraction(){
    grep $1 $v2ray_qr_config_file | awk -F '"' '{print $4}'
}
basic_information(){
    echo -e "${OK} ${Green} V2ray+ws+tls 安装成功" > ${v2ray_info_file}
    echo -e "${Red} V2ray 配置信息 ${Font}" >> ${v2ray_info_file}
    echo -e "${Red} 地址（address）:${Font} $(info_extraction "add") " >> ${v2ray_info_file}
    echo -e "${Red} 端口（port）：${Font} $(info_extraction "port") " >> ${v2ray_info_file}
    echo -e "${Red} 用户id（UUID）：${Font} $(info_extraction '\"id\"')" >> ${v2ray_info_file}
    echo -e "${Red} 额外id（alterId）：${Font} $(info_extraction "aid")" >> ${v2ray_info_file}
    echo -e "${Red} 加密方式（security）：${Font} 自适应 " >> ${v2ray_info_file}
    echo -e "${Red} 传输协议（network）：${Font} $(info_extraction "net") " >> ${v2ray_info_file}
    echo -e "${Red} 伪装类型（type）：${Font} none " >> ${v2ray_info_file}
    echo -e "${Red} 路径（不要落下/）：${Font} $(info_extraction "path") " >> ${v2ray_info_file}
    echo -e "${Red} 底层传输安全：${Font} tls " >> ${v2ray_info_file}
}
show_information(){
    cat ${v2ray_info_file}
}
ssl_judge_and_install(){
    if [[ -f "/data/v2ray.key" && -f "/data/v2ray.crt" ]];then
        echo "证书文件已存在"
    elif [[ -f "~/.acme.sh/${domain}_ecc/${domain}.key" && -f "~/.acme.sh/${domain}_ecc/${domain}.cer" ]];then
        echo "证书文件已存在"
        ~/.acme.sh/acme.sh --installcert -d ${domain} --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc
        judge "证书应用"
    else
        ssl_install
        acme
    fi
}

nginx_systemd(){
    cat>$nginx_systemd_file<<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/etc/nginx/logs/nginx.pid
ExecStartPre=/etc/nginx/sbin/nginx -t
ExecStart=/etc/nginx/sbin/nginx -c ${nginx_dir}/conf/nginx.conf
ExecReload=/etc/nginx/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

judge "Nginx systemd ServerFile 添加"
}

tls_type(){
    if [[ -f "/etc/nginx/sbin/nginx" ]] && [[ -f "$nginx_conf" ]] && [[ "$shell_mode" == "ws" ]];then
        echo "请选择支持的 TLS 版本（default:1）:"
        echo "1: TLS1.1 TLS1.2 and TLS1.3"
        echo "2: TLS1.2 and TLS1.3"
        echo "3: TLS1.3 only"
        read -p  "请输入：" tls_version
        [[ -z ${tls_version} ]] && tls_version=2
        if [[ $tls_version == 3 ]];then
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.3 only ${Font}"
        elif [[ $tls_version == 1 ]];then
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.1 TLSv1.2 TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.1 TLS1.2 and TLS1.3 ${Font}"
        else
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.2 TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.2 and TLS1.3 ${Font}"
        fi
        systemctl restart nginx
        judge "Nginx 重启"
    else
        echo -e "${Error} ${RedBG} Nginx 或 配置文件不存在 或当前安装版本为 h2 ，请正确安装脚本后执行${Font}"
    fi
}
show_access_log(){
    [ -f ${v2ray_access_log} ] && tail -f ${v2ray_access_log} || echo -e "${RedBG}log文件不存在${Font}"
}
show_error_log(){
    [ -f ${v2ray_error_log} ] && tail -f ${v2ray_error_log} || echo -e  "${RedBG}log文件不存在${Font}"
}
ssl_update_manuel(){
    [ -f ${amce_sh_file} ] && "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" || echo -e  "${RedBG}证书签发工具不存在，请确认你是否使用了自己的证书${Font}"
}
bbr_boost_sh(){
    bash <(curl -L -s -k "https://raw.githubusercontent.com/jfplyl999/v2ray/master/tcp.sh")
}
superbench_sh(){
    bash <(curl -L -s -k "https://raw.githubusercontent.com/jfplyl999/v2ray/master/superbench.sh")
}
brook_pf_sh(){
    bash <(curl -L -s -k "https://raw.githubusercontent.com/jfplyl999/v2ray/master/brook-pf.sh")
}
ssrmu_sh(){
    bash <(curl -L -s -k "https://raw.githubusercontent.com/jfplyl999/v2ray/master/ssrmu.sh")
}
yuan_sh(){
    wget -N --no-check-certificate git.io/superupdate.sh && bash superupdate.sh aliyun 
	apt-get update
    apt-get upgrade
	apt-get install curl -y
	}
uninstall_all(){
    stop_process_systemd
    [[ -f $nginx_systemd_file ]] && rm -f $nginx_systemd_file
    [[ -f $v2ray_systemd_file ]] && rm -f $v2ray_systemd_file
    [[ -d $v2ray_bin_file ]] && rm -rf $v2ray_bin_file
    [[ -d $nginx_dir ]] && rm -rf $nginx_dir
    [[ -d $v2ray_conf_dir ]] && rm -rf $v2ray_conf_dir
    [[ -d $web_dir ]] && rm -rf $web_dir
    systemctl daemon-reload
    echo -e "${OK} ${GreenBG} 已卸载，SSL证书文件已保留 ${Font}"
}
judge_mode(){
    if [ -f $v2ray_qr_config_file ]
    then
        if [[ -n $(grep "ws" $v2ray_qr_config_file) ]]
        then
            shell_mode="ws"
        elif [[ -n $(grep "h2" $v2ray_qr_config_file) ]]
        then
            shell_mode="h2"
        fi
    fi
}
install_v2ray_ws_tls(){
    is_root
    check_system
    chrony_install
    dependency_install
    basic_optimization
    domain_check
    port_alterid_set
    v2ray_install
    port_exist_check 80
    port_exist_check ${port}
    nginx_exist_check
    v2ray_conf_add_tls
    nginx_conf_add
    web_camouflage
    ssl_judge_and_install
    nginx_systemd
    vmess_qr_config_tls_ws
    basic_information
    vmess_qr_link_image
    show_information
    start_process_systemd
    enable_process_systemd
    acme_cron_update
}
install_kcp_udp(){
          is_root
          check_system
          chrony_install
          dependency_install
          basic_optimization
		  port_exist_check 8088
		  port_exist_check 9090
		  udp2raw_amd64_check
		  udp2raw_server_install
		  server_linux_amd64_check
		  kcptun_server_install
}
install_kcp_udp_client(){
          is_root
          check_system
          chrony_install
          dependency_install
          basic_optimization
		  port_exist_check 8088
		  port_exist_check 9090
		  udp2raw_amd64_check
		  udp2raw_client_install
		  client_linux_amd64_check
		  kcptun_client_install
}
install_v2_h2(){
    is_root
    check_system
    chrony_install
    dependency_install
    basic_optimization
    domain_check
    port_alterid_set
    v2ray_install
    port_exist_check 80
    port_exist_check ${port}
    v2ray_conf_add_h2
    ssl_judge_and_install
    vmess_qr_config_h2
    basic_information
    vmess_qr_link_image
    show_information
    start_process_systemd
    enable_process_systemd

}
install_nginx_1(){
    is_root
    check_system
    chrony_install
    dependency_install
    basic_optimization
    domain_check
    port_exist_check 443
	nginx_exist_check
    nginx_conf_add_2
    web_camouflage
    ssl_judge_and_install
    nginx_systemd
    start_enable_nginx

}
update_sh(){
    ol_version=$(curl -L -s https://raw.githubusercontent.com/wulabing/V2Ray_ws-tls_bash_onekey/master/install.sh | grep "shell_version=" | head -1 |awk -F '=|"' '{print $3}')
    echo "$ol_version" > $version_cmp
    echo "$shell_version" >> $version_cmp
    if [[ "$shell_version" < "$(sort -rV $version_cmp | head -1)" ]]
    then
        echo -e "${OK} ${Green} 存在新版本，是否更新 [Y/N]? ${Font}"
        read -r update_confirm
        case $update_confirm in
            [yY][eE][sS]|[yY])
                wget -N --no-check-certificate https://raw.githubusercontent.com/wulabing/V2Ray_ws-tls_bash_onekey/master/install.sh
                echo -e "${OK} ${Green} 更新完成 ${Font}"
                ;;
            *)
                exit 0
                ;;
        esac
    else
        echo -e "${OK} ${Green} 当前版本为最新版本 ${Font}"
    fi

}
maintain(){
    echo -e "${RedBG}该选项暂时无法使用${Font}"
    echo -e "${RedBG}$1${Font}"
    exit 0
}
list(){
    case $1 in
        tls_modify)
            tls_type
            ;;
        uninstall)
            uninstall_all
            ;;
        crontab_modify)
            acme_cron_update
            ;;
        boost)
            bbr_boost_sh
            ;;
        *)
            menu
            ;;
    esac
}

menu(){
    echo -e "\t V2ray 安装管理脚本 ${Red}[${shell_version}]${Font}"
    echo -e "\t---authored by wulabing---"
    echo -e "\thttps://github.com/wulabing\n"
    echo -e "当前已安装版本:${shell_mode}\n"

    echo -e "—————————————— 安装向导 ——————————————"""
    echo -e "${Green}0.${Font}  升级 脚本"
    echo -e "${Green}1.${Font}  安装 V2Ray (Nginx+ws+tls)"
    echo -e "${Green}2.${Font}  安装 V2Ray (http/2+tls)"
	echo -e "${Green}17.${Font} 安装 ssrmu"
	echo -e "${Green}21.${Font} 安装 Nginx已固定443"
	echo -e "${Green}22.${Font} 安装 服务器kcptun/udp2raw需要端口8088/9090"
	echo -e "${Green}23.${Font} 安装 客户端kcptun/udp2raw需要端口8088/9090"
	echo -e "${Green}28.${Font} 安装 服务端finalspeed/udp2raw需要端口8089/150"
	echo -e "${Green}31.${Font} 安装 单独安装udp2raw"
	echo -e "${Green}32.${Font} 安装 简单版v2ray"
    echo -e "${Green}3.${Font}  升级 V2Ray core"
    echo -e "—————————————— 配置变更 ——————————————"
    echo -e "${Green}4.${Font}  变更 UUID"
    echo -e "${Green}5.${Font}  变更 alterid"
    echo -e "${Green}6.${Font}  变更 v2aryport"
	echo -e "${Green}24.${Font} 变更 客户端修改服务器ip"
	echo -e "${Green}25.${Font} 变更 客户端修改kcp监听端口"
	echo -e "${Green}26.${Font} 变更 服务器修改kcp监听端口"
	echo -e "${Green}27.${Font} 变更 国内修改github的hosts"
	echo -e "${Green}29.${Font} 变更 服务端fs-udp重启"
	echo -e "${Green}30.${Font} 变更 客户端fs-udp重启"
    echo -e "${Green}7.${Font}  变更 TLS 版本(仅ws+tls有效)"
    echo -e "—————————————— 查看信息 ——————————————"
    echo -e "${Green}8.${Font}  查看 实时访问日志"
    echo -e "${Green}9.${Font}  查看 实时错误日志"
    echo -e "${Green}10.${Font} 查看 V2Ray 配置信息"
    echo -e "—————————————— 其他选项 ——————————————"
    echo -e "${Green}11.${Font} 安装 4合1 bbr 锐速安装脚本"
    echo -e "${Green}12.${Font} 证书 有效期更新"
    echo -e "${Green}13.${Font} 卸载 V2Ray"
	echo -e "${Green}15.${Font} Docker国外安装"
	echo -e "${Green}16.${Font} Docker国内安装"
	echo -e "${Green}18.${Font} superbench测速"
	echo -e "${Green}19.${Font} 端口转发"
	echo -e "${Green}20.${Font} debian更换为阿里源并更新"
    echo -e "${Green}14.${Font} 退出 \n"
	

    read -p "请输入数字：" menu_num
    case $menu_num in
        0)
          update_sh
          ;;
        1)
          shell_mode="ws"
          install_v2ray_ws_tls
          ;;
        2)
          shell_mode="h2"
          install_v2_h2
          ;;
        3)
          bash <(curl -L -s https://install.direct/go.sh)
          ;;
        4)
          read -p "请输入UUID:" UUID
          modify_UUID
          start_process_systemd
          ;;
        5)
          read -p "请输入alterID:" alterID
          modify_alterid
          start_process_systemd
          ;;
        6)
          read -p "请输入连接端口(禁用8088\9090）:" port
          if [[ -n $(grep "ws" $v2ray_qr_config_file) ]]
          then
              modify_nginx_port
			  modify_kcptun_port
          elif [[ -n $(grep "h2" $v2ray_qr_config_file) ]]
          then
              modify_inbound_port
			  modify_kcptun_port
          fi
          start_process_systemd
		  kcptun_udp2raw_restart
          ;;
        7)
          tls_type
          ;;
        8)
          show_access_log
          ;;
        9)
          show_error_log
          ;;
        10)
          basic_information
          vmess_qr_link_image
          show_information
          ;;
        11)
          bbr_boost_sh
          ;;
        12)
          stop_process_systemd
          ssl_update_manuel
          start_process_systemd
          ;;
        13)
          uninstall_all
          ;;
        14)
          exit 0
          ;;
		15)
          docker_install_1
          ;;
		16)
          docker_install_2 
          ;;
		17)
          ssrmu_sh 
          ;;
		18)
          superbench_sh 
          ;;
        19)
          brook_pf_sh 
          ;;
        20)
          yuan_sh 
          ;;
        21)
          install_nginx_1 
          ;;
        22)
          install_kcp_udp
          ;;
        23)
          install_kcp_udp_client
          ;;
		24)
          Set_IP_pf
		  kcptun_udp2raw_client_restart
          ;;
        25)
		  kcptun_port_alterid_set
	      modify_kcptun_port_client
		  kcptun_udp2raw_client_restart
          ;;
        26)
		  kcptun_port_alterid_set
	      modify_kcptun_port
		  kcptun_udp2raw_restart
          ;;
        27)
		  changehosts
          ;;
        28)
		  udp2raw_amd64_check 
		  finalspeed_server_install
          ;;
        29)
		  finalspeed_udp2raw_restart
          ;;
        30)
		  finalspeed_udp2raw_client_restart
          ;;
        31)
		  udp2raw_amd64_check
		  wget -N --no-check-certificate https://raw.githubusercontent.com/jfplyl999/v2ray/master/run.sh -O run.sh 
	      chmod +x run.sh
          ;;
        32)
		  bash <(curl -s -L https://git.io/v2ray.sh)
          ;;		  
        *)
          echo -e "${RedBG}请输入正确的数字${Font}"
          ;;
    esac
}

judge_mode
list $1
