#!/bin/bash

set -e

ping_regex='([0-4]) received'
# test if facebook can be resolved
echo "testing connection..."
ping_results=$(ping -c 4 -q facebook.com)
if [[ $ping_results =~ $ping_regex ]]; then
    packets_recieved="${BASH_REMATCH[1]}"
    if [[ $packets_recieved -ge 3 ]]; then
        echo "already online, exiting"
        exit
    fi
    echo "testing inconclusive"
else
    echo "no connection"
fi

# scan for wifi networks and save each line of the open ones to a variable
IFS=$'\n'
open_networks=($(iwlist wlan0 scan | grep -A 2 -B 5 "Encryption key:off"))
unset IFS

# regular expressions
ssid_regex='ESSID:"(.*)"'
quality_regex='Quality=(100|[0-9]{1,2})/100'
signal_regex='Signal level=(100|[0-9]{1,2})/100'
int_regex='(\d{1,3})'

# loop through open network data
count=0
for network_raw in "${open_networks[@]}"
do
    # save ssid's in an array
    if [[ $network_raw =~ $ssid_regex ]]; then
        ssid[$count]="${BASH_REMATCH[1]}"
    # save quality and signal in arrays
    elif [[ $network_raw =~ $quality_regex ]]; then
        quality[$count]="${BASH_REMATCH[1]}"
        [[ $network_raw =~ $signal_regex ]]
        signal[$count]="${BASH_REMATCH[1]}"

        # save indexes of arrays (for sorting)
        indexes[$count]=$count
        # increment counter to next network
        count=$(($count + 1))
    fi
done

echo ${ssid[0]}
echo ${quality[0]}
echo ${signal[0]}

# sort networks by order of quality or signal
readarray -t sorted_indexes < <(printf '%s\0' "${indexes[@]}" | sort -z | xargs -0n1)

# loop through networks in order as above
for network in "${sorted_indexes[@]}"
do
    wpa_supplicant=/etc/wpa_supplicant/wpa_supplicant.conf
    wpa_supplicant_bkup=/etc/wpa_supplicant/wpa_supplicant.conf.bkup
    echo "saving wpa_supplicant.conf"
    cp $wpa_supplicant $wpa_supplicant_bkup

    echo "modifying wpa_supplicant"
    wpa_supplicant_content="\n\nnetwork={\n\tssid=\"${ssid[$network]}\"\n\tkey_mgmt=NONE\n\tauth_alg=OPEN\n}"
    # echo -e $wpa_supplicant_content >> "$wpa_supplicant"

    # attempt to connect to network
    echo "connecting (to ${ssid[$network]})"
    $(ifup wlan0 > /dev/null 2>&1)

    wait

    # test if facebook can be resolved
    echo "pinging facebook"
    ping_results=$(ping -c 4 -q facebook.com 2>&1)

    if [[ $ping_results =~ $ping_regex ]]; then
        packets_recieved="${BASH_REMATCH[1]}"

        if [ $packets_recieved -ge 3 ]; then
            echo "successfully connected to ${ssid[$network]} and online"
            exit
        else
            echo "facebook can't be reached on ${ssid[$network]}"
            rm $wpa_supplicant
            mv $wpa_supplicant_bkup $wpa_supplicant
        fi
    else
        echo "ping test failed: $ping_results"
    fi
    echo "trying next network"
done
