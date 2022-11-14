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

command="rtla timerlat hist --auto ${MAXLATENCY} --duration ${DURATION} --cpus ${cpulist} --dma-latency 0 ${EXTRA}"

echo "running cmd: ${command}"
if [ "${manual:-n}" == "n" ]; then
    if [ "${delay:-0}" != "0" ]; then
        echo "sleep ${delay} before test"
        sleep ${delay}
    fi
    $command
else
    sleep infinity
fi

sleep infinity

# kill stress before exit 
tmux kill-session -t stress 2>/dev/null

if [ "${DISABLE_CPU_BALANCE:-n}" == "y" ]; then
    enable_balance
fi

