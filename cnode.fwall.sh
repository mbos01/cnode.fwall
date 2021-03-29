#!/bin/bash

###################################################################

# Script Name	: cnode.fwall.sh - v.0.2
# Description	: scans incoming connections to cnode port and bans ip when threshold is exceeded
# Config	: cnode.fwall.config
# Dependencies  : iptables, sqlite3, netstat, mail

# Author       	: Bos020 - the.adahou.se - cardanopools.io
# Contact       : martijn@cardanopools.io - twitter.com/Bos020

##################################################################

function installSvc {
        svcfile=$(cat cnode.fwall.service)
        svcfile=${svcfile//\[WORKINGDIR\]/$(pwd)}
        echo "$svcfile" > "/etc/systemd/system/cnode.fwall.service"

        #reload, enable, start
        systemctl daemon-reload
        systemctl enable cnode.fwall.service
        systemctl start cnode.fwall.service

        echo "Service is installed."; echo
}

#load config
if test -f "cnode.fwall.config"; then
        . cnode.fwall.config
else
        echo; echo "cnode.fwall.config does not exist!"; echo
        exit
fi

#script must be run as root
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo; echo "Please run as root."; echo
    exit
fi

#check dependencies
dep=($IPTABLES_EXE $SQLITE_EXE $NETSTAT_EXE $MAIL_EXE); missing=(); for d in ${dep[@]}; do
        if ! command -v $d  &> /dev/null
	then
                missing+="$d "
        fi
done

if ! [[ -z ${missing[@]} ]]; then
        echo; echo $"Please install missing dependencies first."; echo
        for m in ${missing[*]}; do echo "$m could not be found."; done
        echo; exit
fi

#are we installing?
if [[ $1 = "--install" ]]; then
	if systemctl list-units --full -all | grep "cnode.fwall"; then
        	echo "Service already exists."
	else
	        #install as a service
	        while true; do
        	        read -p "Script will be installed in $(pwd), proceed? [Y/N]" reply
                	case $reply in
	                        [yY]* ) installSvc; break;;
        	                [nN]* ) break;;
                	        * ) echo "Please choose Y or N.";;
	                esac
        	done
	fi
	exit
fi

#does db exist? if not: create the db
if [[ ! -e $IPBAN_DB ]]; then
	echo "[cnode.fwall] $IPBAN_DB does not exist, creating db."
	$SQLITE_EXE $IPBAN_DB "create table ipban (id INTEGER PRIMARY KEY,dt datetime default current_timestamp,ip TEXT);"
fi

# on startup first setup initial iptables

#flush iptables
echo "[cnode.fwall] Flush iptables."
$IPTABLES_EXE -F

#read manual rules (these are the rules you want to be always effective) and construct initial iptables
while read rule; do
        if ! [[ -z $rule ]]; then
		echo "[cnode.fwall] insert ${rule//iptables/$IPTABLES_EXE}"
		${rule//iptables/$IPTABLES_EXE}
        fi
done < $IPTABLES_RULES

#get active bans from database and insert them in iptables
$SQLITE_EXE $IPBAN_DB "SELECT ip FROM ipban GROUP BY ip;" | while read ip; do
	#insert existing bans
	echo "[cnode.fwall] insert ACTIVE BAN for $ip"
        $IPTABLES_EXE $(echo "-I INPUT -s $ip -j DROP")
done

#some variable formatting
BAN_TIME=${BAN_TIME//m/}

#construct excluded addresses
oldIFS=$IFS; IFS="|"
read -r -a excluded <<< "$EXCLUDE_IP"; IFS=$oldIFS

#daemonized from here
while true; do
	#get incoming connections for cardano port
	arr=()
	for i in $(netstat -ano | grep -w $CARDANO_PORT | grep ESTABLISHED | awk '{print $5}' | grep -v $CARDANO_PORT); do
		arr+=( $(echo $i | cut -f1 -d ":") )
	done

	#sort array
	arr=( $(for each in ${arr[@]}; do echo $each; done | sort) )

	#loop through array and count occurences
	for ip in ${arr[@]}; do
	        if [[ -z "$prev" ]]; then
	                prev=$ip
	                count=1
			ban=false
	        elif [[ $prev = $ip ]]; then
			if [[ $ban = false ]]; then
		                count=$((count+1))
			fi
	        else
	                prev=$ip
	                count=1
			ban=false
	        fi

		#whenever threshold exceeded do this
		if [[ $count -gt $CONNECTIONS_THRESHOLD &&  $ban = false && " ${excluded[*]} " != *"$ip"* ]]; then
			if ! [[ $($SQLITE_EXE $IPBAN_DB "SELECT ip FROM ipban WHERE ip = '$ip';") ]]; then
				echo "[cnode.fwall] ADD BAN for $ip."

		        	#add rules
		        	$SQLITE_EXE $IPBAN_DB  "insert into ipban (ip) values ('$ip');"
				$IPTABLES_EXE -I INPUT 1 -s $ip -j DROP

				#send mail
				if ! [[ -z $MAIL_EXE ]]; then
					$MAIL_EXE -s "[cnode.fwall] - $HOSTNAME: NEW BAN" -a "FROM:$MAIL_FROM" $MAIL_TO <<< "IP $ip has just been banned for a period of $BAN_TIME minutes after having exceeded the threshold of $CONNECTIONS_THRESHOLD connections."
				fi
				ban=true

				#close established connections
				oldIFS=$IFS; IFS=":"
				ss | grep $ip | awk '{print $6}' | while read c; do
					read -r -a cconn <<< $c
					ss -K dst ${cconn[0]} dport = ${cconn[1]}
				done; IFS=$oldIFS
			fi
		fi
	done

	#let's do some maintenance
	oldIFS=$IFS; IFS="|"
	#is ban time expired? delete the rules from the db, update iptables
	$SQLITE_EXE $IPBAN_DB "SELECT id,ip FROM ipban WHERE ((strftime('%s', 'now') - strftime('%s', dt)) / 60) > $BAN_TIME;" | while read id ip; do
		echo "[cnode.fwall] REMOVE BAN from $ip."

		#delete rules
		$SQLITE_EXE $IPBAN_DB "DELETE FROM ipban WHERE id = $id;"
		$IPTABLES_EXE -D INPUT -s $ip -j DROP
	done; IFS=$oldIFS

	#reset variables
	prev=""; count=0; ban=false

	#wait a bit
	sleep $INTERVAL
done

