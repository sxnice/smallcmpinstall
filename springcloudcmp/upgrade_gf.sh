#!/bin/bash
#set -x
#set -eo pipefail
shopt -s nullglob
source ./colorecho

nodetyper=1
nodeplanr=1
nodenor=1
eurekaipr=localhost
dcnamer="DC1"
JDK_DIR="/usr/java"


#---------------可修改配置参数------------------
#安装目录
CURRENT_DIR="/springcloudcmp"
#用户名，密码
cmpuser="cmpimuser"
cmppass="Pbu4@123"
#IM节点IP组，用空格格开
SSH_H="10.143.132.187"
#扩容采集节点组，用空格格开
GF_H="10.143.132.189 10.143.132.190"
#-----------------------------------------------
declare -a GF_HOST=($GF_H)
declare -a SSH_HOST=($SSH_H)
declare -a IM_HOST=($SSH_H $GF_H)

#检测操作系统
check_ostype(){
	local ostype=`ssh -n $1 head -n 1 /etc/issue | awk '{print $1}'`
	if [ "$ostype" == "Ubuntu" ]; then
		local version=`ssh -n $1 head -n 1 /etc/issue | awk  '{print $2}'| awk -F . '{print $1}'`
		echo ubuntu_$version
	else
		local centos=`ssh -n $1 rpm -qa | grep sed | awk -F . '{print $4}'`
		if [ "$centos" == "el6" ]; then
			echo centos_6
		elif [ "$centos" == "el7" ]; then
			echo centos_7
		fi
	fi
}
#检测安装软件
install-interpackage(){
	echo_green "环境检测开始..."
	for i in "${GF_HOST[@]}"
            do
		echo "安装依赖包到"$i
		local ostype=`check_ostype $i`
		local os=`echo $ostype | awk -F _ '{print $1}'`
		if [ "$os" == "centos" ]; then
        		local iptables=`ssh -n "$i" rpm -qa |grep iptables |wc -l`
       			 if [ "$iptables" -gt 1 ]; then
                		echo "iptables 已安装"
        		else
                		if [ "${ostype}" == "centos_6" ]; then
                        		 scp  ../packages/centos6_iptables/* "$i":/root/
                         		 ssh -n $i rpm -Uvh ~/iptables-1.4.7-16.el6.x86_64.rpm
				elif [ "$ostype" == "centos_7" ]; then
                                        scp -r ../packages/centos7_iptables "$i":/root/
                                        ssh -Tq $i <<EOF
                                        rpm -Uvh --replacepkgs ~/centos7_iptables/*
                                        exit
EOF
                                fi
        		fi
	        	local lsof=`ssh -n "$i" rpm -qa |grep lsof |wc -l`
                	 if [ "$lsof" -gt 0 ]; then
                        	echo "lsof 已安装"
               		 else
                		if [ "${ostype}" == "centos_6" ]; then
                        		 scp  ../packages/centos6_lsof/* "$i":/root/
                         		 ssh -n $i rpm -Uvh ~/lsof-4.82-5.el6.x86_64.rpm
               			 elif [ "${ostype}" == "centos_7" ]; then
                        		 scp ../packages/centos7_lsof/* "$i":/root/
                         		 ssh -n $i rpm -Uvh ~/lsof-4.87-4.el7.x86_64.rpm
               			 fi
               		 fi
		elif [ "$os" == "ubuntu" ]; then
			if [ "$ostype" == "ubuntu_12" ]; then
				echo_red "$ostype"暂不提供安装
				exit
			elif [ "$ostype" == "ubuntu_14" ]; then
				scp  ../packages/ubuntu14/* "$i":/root/
                                ssh -n $i dpkg -i ~/lsof_4.86+dfsg-1ubuntu2_amd64.deb ~/iptables_1.4.21-1ubuntu1_amd64.deb ~/libnfnetlink0_1.0.1-2_amd64.deb ~/libxtables10_1.4.21-1ubuntu1_amd64.deb
			elif [ "$ostype" == "ubuntu_16" ]; then
				echo_red "$ostype"暂不提供安装                                
                                exit
			else
				echo_red "$ostype"暂不提供安装
                                exit
			fi
		fi
                echo "安装jdk1.8到节点"$i
                ssh -Tq "$i" <<EOF
                sed -i /'umask 077'/d ~/.bashrc
                source ~/.bashrc
		rm -rf "$JDK_DIR"
		mkdir -p "$JDK_DIR"
		chmod 755 "$JDK_DIR"
EOF
		scp -r ../packages/jdk/* "$i":"$JDK_DIR"
		scp ../packages/jce/* "$i":"$JDK_DIR"/jre/lib/security/
		ssh -Tq $i <<EOF
		    chmod 755 "$JDK_DIR"/bin/*
		    sed -i /JAVA_HOME/d /etc/profile
		    echo JAVA_HOME="$JDK_DIR" >> /etc/profile
		    echo PATH='\$JAVA_HOME'/bin:'\$PATH' >> /etc/profile
		    echo CLASSPATH='\$JAVA_HOME'/jre/lib/ext:'\$JAVA_HOME'/lib/tools.jar >> /etc/profile
  	            echo export JAVA_HOME CLASSPATH PATH>> /etc/profile
	            source /etc/profile
		    su - $cmpuser
                    sed -i /JAVA_HOME/d ~/.bashrc
                    echo JAVA_HOME="$JDK_DIR" >> ~/.bashrc
                    echo PATH='\$JAVA_HOME'/bin:'\$PATH' >> ~/.bashrc
                    echo CLASSPATH='\$JAVA_HOME'/jre/lib/ext:'\$JAVA_HOME'/lib/tools.jar >> ~/.bashrc
                    echo export JAVA_HOME CLASSPATH PATH>> ~/.bashrc
		    exit
		
EOF
                echo "系统配置节点"$i
                ssh -Tq "$i" <<EOF
                    sed -i /$cmpuser/d /etc/security/limits.conf
                    echo $cmpuser soft nproc unlimited >>/etc/security/limits.conf
                    echo $cmpuser hard nproc unlimited >>/etc/security/limits.conf
                    sed -i /limits/d /etc/security/limits.conf
                    echo session required pam_limits.so >>/etc/pam.d/login
                    exit
EOF
		echo "complete..." 
	done
	echo_green "检测安装环境完成..."
}

#建立对等互信
ssh-interconnect(){
    	echo_green "建立对等互信开始..."
	local ssh_init_path=./ssh-init.sh
	$ssh_init_path ${IM_HOST[@]}
	if [ $? -eq 1 ]; then
		exit 1
	fi
	echo_green "建立对等互信完成..."
}

#创建普通用户cmpimuser
user-internode(){
	echo_green "建立普通用户开始..."
	for i in "${GF_HOST[@]}"
	do
	echo =======$i=======
	ssh -Tq $i <<EOF
	groupadd $cmpuser
 	useradd -m -s  /bin/bash -g $cmpuser $cmpuser
 	usermod -G $cmpuser $cmpuser
	echo "$cmpuser:$cmppass" | chpasswd
EOF
        done
	echo_green "建立普通用户完成..."
        
}

#复制文件到各节点
copy-internode(){
	echo_green "复制文件到各节点开始..."
	case $nodeplanr in
          [1-4]) #部署
                for i in "${GF_HOST[@]}"
                do
                        echo "复制文件到"$i 
                        #放根目录下
                        ssh -n $i mkdir -p $CURRENT_DIR
                        scp -r ./background ./im ./config startIM.sh startIM_BX.sh stopIM.sh imstart_chk.sh  "$i":$CURRENT_DIR
                        #赋权
                        ssh -Tq $i <<EOF
                        rm -rf /tmp/spring.log
                        rm -rf /tmp/modelTypeName.data
                        chown -R $cmpuser.$cmpuser $CURRENT_DIR
                        chmod 740 "$CURRENT_DIR"
                        chmod 740 "$CURRENT_DIR"/*.sh
                        chmod 740 "$CURRENT_DIR"/background
                        chmod 640 "$CURRENT_DIR"/background/*.jar
                        chmod 740 "$CURRENT_DIR"/config
                        chmod 740 "$CURRENT_DIR"/im
                        chmod 640 "$CURRENT_DIR"/im/*.jar
                        chmod 740 "$CURRENT_DIR"/background/*.sh
                        chmod 740 "$CURRENT_DIR"/im/*.sh
                        chmod 640 "$CURRENT_DIR"/im/*.war
                        chmod 600 "$CURRENT_DIR"/config/*.yml
                        su $cmpuser
                        umask 077
        #               rm -rf "$CURRENT_DIR"/data
                        mkdir  "$CURRENT_DIR"/data
        #               rm -rf "$CURRENT_DIR"/activemq-data
                        mkdir  "$CURRENT_DIR"/activemq-data
                        rm -rf "$CURRENT_DIR"/logs
                        mkdir  "$CURRENT_DIR"/logs
                        rm -rf "$CURRENT_DIR"/temp
                        mkdir  "$CURRENT_DIR"/temp
                        exit
EOF
                echo "complete..."
                done
            ;;
          0)
            echo "nothing to do...."
            ;;
         esac
	echo_green "复制文件到各节点完成..."
}


#配置扩容采集节点环境变量
env_gfnode(){
                echo_green "配置扩容采集节点环境变量开始..."
                for j in "${GF_HOST[@]}"
		do
		echo "配置节点"$j
			
			if [ $nodeplanr -ne 1 ]; then
			echo "节点类型，请输入编号："  
			echo "2-----采集节点."    
			echo "3-----控制以及采集节点."    
			read nodetyper 
			
			echo "请输入主控制节点IP："  
			read eurekaipr 
			fi

			if [ $nodetyper -eq 2 ] || [ $nodetyper -eq 3 ]; then
			read -t 5 -p "请输入采集节点名称，如DC1:" dcnamer
                        dcnamer=${dcnamer:-"DC1"}
			fi
			
			nodenor=0
			
			
			echo "设置nodeplan="$nodeplanr
			echo "设置nodetype="$nodetyper
			echo "设置nodeno="$nodenor	
			echo "设置eurekaip="$eurekaipr
			echo "设置dcname="$dcnamer

			echo "节点："$j
			
			ssh -Tq $j <<EOF
                        sed -i /nodeplan/d /etc/environment
			sed -i /nodetype/d /etc/environment
			sed -i /nodeno/d /etc/environment
			sed -i /eurekaip/d /etc/environment
			sed -i /eurekaiprep/d /etc/environment
			sed -i /dcname/d /etc/environment
			
			echo "nodeplan=$nodeplanr export nodeplan">>/etc/environment
			echo "nodetype=$nodetyper export nodetype">>/etc/environment
			echo "nodeno=$nodenor export nodeno">>/etc/environment 
			echo "eurekaip=$eurekaipr export eurekaip">>/etc/environment
			echo "eurekaiprep=$eurekaipr export eurekaiprep">>/etc/environment
			echo "dcname=$dcnamer export dcname">>/etc/environment 			
			source /etc/environment
			su - $cmpuser
			sed -i /nodeplan/d ~/.bashrc
                        sed -i /nodetype/d ~/.bashrc
                        sed -i /nodeno/d ~/.bashrc
                        sed -i /eurekaip/d ~/.bashrc
			sed -i /eurekaiprep/d ~/.bashrc
                        sed -i /dcname/d ~/.bashrc
			
			echo "umask 077" >> ~/.bashrc
			echo "CURRENT_DIR=$CURRENT_DIR export CURRENT_DIR" >> ~/.bashrc
			echo "nodeplan=$nodeplanr export nodeplan">>~/.bashrc
                        echo "nodetype=$nodetyper export nodetype">>~/.bashrc
                        echo "nodeno=$nodenor export nodeno">>~/.bashrc 
                        echo "eurekaip=$eurekaipr export eurekaip">>~/.bashrc
			echo "eurekaiprep=$eurekaipr export eurekaiprep">>~/.bashrc
                        echo "dcname=$dcnamer export dcname">>~/.bashrc 
			source ~/.bashrc
			exit
EOF
		
		echo "complete..." 
		done
		echo_green "配置扩容采集节点环境变量结束..."
}

#配置iptables
iptable_internode(){
        echo_green "配置各节点iptables开始..."
        local iptable_path=./iptablescmp.sh
        $iptable_path "${IM_HOST[@]}"
	echo_green "配置各节点iptables结束..."
}

#启动im
start_internode(){
		echo_green "启动采集开始..."
		for i in "${GF_HOST[@]}"
		do
		echo "启动节点"$i
		ssh -nf $i 'su - '$cmpuser' -c '$CURRENT_DIR'/startIM_BX.sh >/dev/null'
		echo "发启启动指令成功"
		done
		
		for i in "${GF_HOST[@]}"
		do
		echo "启动节点"$i
		 ssh -Tq $i <<EOF
		 su - $cmpuser
		 source /etc/environment
		 umask 077
		 cd "$CURRENT_DIR"
		 ./imstart_chk.sh
		 exit
EOF
		echo "节点启动成功"
		done
		echo_green "启动采集完成..."
}



#echo_yellow "-----------一键安装（增量）说明-------------------"
#echo_yellow "1、可安装JDK软件;"
#echo_yellow "2、可安装有iptables lsof软件;"
#echo_yellow "3、初始化时，建议使用root用户安装;"
#echo_yellow "4、确保.sh有执行权限，并且使用 ./xxx.sh执行;"
#echo_yellow "-------------------------------------------"
#echo_green "单机版（小规模）方案，请输入编号：" 
#sleep 3
#clear
echo "1-----4台服务器(每台16G内存.3台控制节点，1台采集节点) + 扩容采集节点N台"  

while read item
do
  case $item in
    [1])
        nodeplanr=3
		ssh-interconnect
		user-internode
		install-interpackage
		copy-internode
		env_gfnode
		iptable_internode
		start_internode
        break
        ;;
     0)
        echo "退出"
        exit 0
        ;;
     *)
        echo_red "输入有误，请重新输入！"
        ;;
  esac
done
