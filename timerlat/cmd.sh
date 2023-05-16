#!/bin/bash

# env vars:
#   DURATION (default "24h")
#   MAXLATENCY (default 20 (us))
#   DISABLE_CPU_BALANCE (default "n", choice y/n)
#   EXTRA (default "")
#   stress (default "false", choices false/true)
#   delay (default 0, specify how many seconds to delay before test start)

source common-libs/functions.sh

function sigfunc() {
    tmux kill-session -t stress 2>/dev/null
    if [ "${DISABLE_CPU_BALANCE:-n}" == "y" ]; then
        enable_balance
    fi
    exit 0
}

echo "############# dumping env ###########"
env
echo "#####################################"

echo " "
echo "########## container info ###########"
echo "/proc/cmdline:"
cat /proc/cmdline
echo "#####################################"

echo "**** uid: $UID ****"
if [[ -z "${DURATION}" ]]; then
    DURATION="24h"
fi

if [[ -z "${MAXLATENCY}" ]]; then
    MAXLATENCY="20"
fi

if [[ -z "${EXTRA}" ]]; then
    EXTRA=""
fi

if [[ -z "${stress}" ]]; then
    stress="false"
elif [[ "${stress}" != "stress-ng" && "${stress}" != "true" ]]; then
    stress="false"
else
    stress="true"
fi

release=$(cat /etc/os-release | sed -n -r 's/VERSION_ID="(.).*/\1/p')

for cmd in tmux rtla; do
    command -v $cmd >/dev/null 2>&1 || { echo >&2 "$cmd required but not installed. Aborting"; exit 1; }
done

cpulist=`get_allowed_cpuset`
echo "allowed cpu list: ${cpulist}"

uname=`uname -nr`
echo "$uname"

cpulist=`convert_number_range ${cpulist} | tr , '\n' | sort -n | uniq`

declare -a cpus
cpus=(${cpulist})

if [ "${DISABLE_CPU_BALANCE:-n}" == "y" ]; then
    disable_balance
fi

trap sigfunc TERM INT SIGUSR1

# stress run in each tmux window per cpu
if [[ "$stress" == "true" ]]; then
    yum install -y stress-ng 2>&1 || { echo >&2 "stress-ng required but install failed. Aborting"; sleep infinity; }
    tmux new-session -s stress -d
    for w in $(seq 1 ${#cpus[@]}); do
        tmux new-window -t stress -n $w "taskset -c ${cpus[$(($w-1))]} stress-ng --cpu 1 --cpu-load 100 --cpu-method loop"
    done
fi

cyccore=${cpus[1]}
cindex=2
ccount=1
while (( $cindex < ${#cpus[@]} )); do
    cyccore="${cyccore},${cpus[$cindex]}"
    cindex=$(($cindex + 1))
    ccount=$(($ccount + 1))
done

sibling=`cat /sys/devices/system/cpu/cpu${cpus[0]}/topology/thread_siblings_list | awk -F '[-,]' '{print $2}'`
if [[ "${sibling}" =~ ^[0-9]+$ ]]; then
    echo "removing cpu${sibling} from the cpu list because it is a sibling of cpu${cpus[0]} which will be the mainaffinity"
    cyccore=${cyccore//,$sibling/}
    ccount=$(($ccount - 1))
fi
echo "new cpu list: ${cyccore}"

export CPUS=${cyccore}
export MAINCPUS=${cpus[0]}

if [ "${manual:-n}" == "n" ]; then
    if [ "${delay:-0}" != "0" ]; then
        echo "sleep ${delay} before test"
        sleep ${delay}
    fi
    echo "now running ..."
    python -c 'import os; maxlat=str(os.getenv("MAXLATENCY")); duration=str(os.getenv("DURATION")); cpus=os.getenv("CPUS"); maincpus=str(os.getenv("MAINCPUS")); extra=os.getenv("EXTRA"); os.system("timerlat hist --auto "+maxlat+" --duration "+duration+" --cpus "+cpus+" -H "+maincpus+" --dma-latency 0 --dump-task " + extra)'
else
    sleep infinity
fi

echo "done! if a trace was collected you can retreive it with 'oc rsync timerlat:/root/timerlat_trace.txt .'"

sleep infinity

# kill stress before exit 
tmux kill-session -t stress 2>/dev/null

if [ "${DISABLE_CPU_BALANCE:-n}" == "y" ]; then
    enable_balance
fi

