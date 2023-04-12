#!/bin/bash
# Bash Menu Script Example

unset options
PS3='Please enter your choice: '
options=("setup" "migrate" "harvest" "deploy strategy" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "harvest")
	    read -p 'check trigger): ' trigger
            (cd ..; brownie run scripts/scripts/harvest.py trigger --network $ETH_NETWORK)
            ;;
        "setup")
            (cd ..; rm -r build)
            (cd ..; brownie run scripts/scripts/setup.py deploy --network $ETH_NETWORK)
            ;;
        "migrate")
	    read -p 'min 3Crv amount (1M == 1E24): ' min_3crv
	    read -p 'min Shares amount (1M == 1E24): ' min_shares
            (cd ..; brownie run scripts/scripts/setup.py harvest_all --network $ETH_NETWORK)
            (cd ..; brownie run scripts/scripts/setup.py schedule_migration --network $ETH_NETWORK)
            (cd ..; brownie run scripts/scripts/setup.py migrate $min_3crv $min_shares --network $ETH_NETWORK)
            ;;
        "deploy strategy")
	    read -p 'convex pid: ' pid
	    read -p 'strategy debt ratio: ' debt_ratio
            (cd ..; rm -r build)
            (cd ..; brownie run scripts/scripts/setup.py deploy_strategy $debt_ratio $pid --network $ETH_NETWORK)
            ;;
        "Quit")
            break
            ;;
        *) echo invalid option;;
    esac
done
