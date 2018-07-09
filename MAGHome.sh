#!/bin/bash
# The controller of my home

CMDS="Capture_Video Take_Image Update_Server_Adr CoolerON CoolerOFF Shell"
LOGFILE="/var/log/ConStat"
SERVER=""
SRVPORT=
NSCTR=0

exec 1>>$LOGFILE
exec 2>&1

Reset_Modem()
{
	# just set the GPIO pin to low and high again
	echo "modem should restart"
}

RUN_CMD()
{
	CMD=$(cat /tmp/CMD | head -n1)
	case $CMD in
	"Capture_Video")
		FName=$(echo "/tmp/MAGHome_$(date +%F-%H-%M-%S).avi")
		Mins=$(head -n2 /tmp/CMD | tail -n1)
		Secs=$(head -n3 /tmp/CMD | tail -n1)
		streamer -t $Mins:$Secs -o $FName -r 50 -f mjpeg -F stereo &>/dev/null
		scp -P $SRVPORT $FName root@$SERVER:/opt/HomeVideos >/dev/null
		if [ $? -eq 0 ]
		then
			rm -f $Fname
		fi
		echo "Video captured successfully @ $(date)"
		;;
	"Take_Image")
		FName=$(echo "/tmp/MAGHome_$(date +%F-%H-%M-%S).jpeg")
		streamer -o $FName &>/dev/null
		scp -P $SRVPORT $FName root@$SERVER:/opt/HomeImages >/dev/null
		if [ $? -eq 0 ]
		then
			rm -f $FName
		fi

		echo "Image taken successfully @ $(date)"
		;;
	"Update_Server_Adr")
		echo "Update"
		;;
	"CoolerON")
		echo "cooler on"
		;;
	"CoolerOFF")
		echo "cooler off"
		;;
	"Shell")
		cat /tmp/CMD | tail -n +2 > /tmp/cmdScript.sh
		chmod +x /tmp/cmdScript.sh
		$(/tmp/cmdScript.sh)
		;;
	*)
		echo "Unknown command: $CMD @ $(date)"
		;;
	esac
}




Check_Connection()
{
	
	# Check to see if we have obtained an IP address or not (IP rage: 192.168.1.x/24)
	MyIP=$(ip ad | grep wlan | tail -n1 |cut -f6 -d " " | cut -f1,2,3 -d .)
	if [ $MyIP != "192.168.1" ]
	then
		echo "NoIP"
		return
	fi
	
	# Check to see if we can see th AccessPoint or not (IP: 192.168.1.1)
	ping -W5 -c1 192.168.1.1 &>/dev/null
	if [ $? -ne 0 ]
	then
		echo "NoAP"
		return
	fi
	
	# Check to see if we are connected to the internet 
	ping -W5 -c1 4.2.2.2 &>/dev/null
	if [ $? -ne 0 ]
	then
		echo "NoNet"
		return
	fi

	# Check to see if we can see our server or not	
	ping -W5 -c1 $SERVER &>/dev/null
	if [ $? -ne 0 ]
	then
		echo "NoSrv"
		return
	fi
	
	# We are connected!
	echo "Conn"

}
	



while [ true ]
do
	
	case $(Check_Connection) in

	"NoSrv")
		echo "Server is not responding @ $(date)" 
		echo "Just waiting for 5 minutes..." 
		sleep $(expr 360 + $NSCTR)
		NSCTR=$((NSCTR+1))
		continue
		;;
	"NoNet")
		echo "No internet connection @ $(date)" 
		echo "Restarting the modem" 
		$(Reset_Modem)
		sleep 120
		continue
		;;
	"NoAP")
		echo "AccessPoint unreachable @ $(date)" 
		echo "Restarting the modem" 
		$(Reset_Modem)
		sleep 120
		continue
		;;
	"NoIP")
		echo "No IP address assigned to us @ $(date)" 
		echo "Renewing IP address:" 
		dhclient -r
		ifdown wlan0
		ifup wlan0
		dhclient
		echo "Finished Reneweing IP address @ $(date)"
		continue
		
		;;
	"Conn")
		echo "No Connection Problem"  > /dev/null
		;;
	*)
		echo "ODD!"
	esac


	# Now we know that we are sure that we can see the server

	# Check to see if there are any commands to do
	ssh -p $SRVPORT root@$SERVER "ls /opt/MAGHome/CMD" &>/dev/null
	res=$?
	if [ $res -eq 2 ]
	then
		#No command to execute...
		continue
	fi
	if [ $res -ne 0 ]
	then
		echo "Something went wrong while checking for new commands @ $(date)"
		echo "Error code: $res"
		continue
	fi

	# Now there is a CMD file waiting for us on the server...
	scp -P $SRVPORT root@$SERVER:/opt/MAGHome/CMD /tmp/CMD
	if [ $? -eq 0 ]
	then
		ssh -p $SRVPORT root@$SERVER "rm -f /opt/MAGHome/CMD" 
		echo $(RUN_CMD)
	fi

	
	sleep 1
done
