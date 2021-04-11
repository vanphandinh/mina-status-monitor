#!/bin/bash
MINA_STATUS=""
STAT=""
ARCHIVESTAT=0
CONNECTINGCOUNT=0
OFFLINECOUNT=0
TOTALCONNECTINGCOUNT=0
TOTALOFFLINECOUNT=0
TOTALSTUCK=0
ARCHIVEDOWNCOUNT=0
TIMEZONE=Asia/Ho_Chi_Minh
SNARKWORKERTURNEDOFF=1 ### assume snark worker not turned on for the first run
DISABLESNARKWORKER=FALSE ### disable/enable snark worker
SNARKWORKERSTOPPEDCOUNT=0
readonly SECONDS_PER_MINUTE=60
readonly MINUTES_PER_HOUR=60
readonly HOURS_PER_DAY=24
FEE=0.001 ### SET YOUR SNARK WORKER FEE HERE ###
SW_ADDRESS= ### SET YOUR SNARK WORKER ADDRESS HERE ###
CONTAINER_NAME="mina"
GRAPHQL_URI=""

package=`basename "$0"`
while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo "./$package - attempt to monitor the mina daemon"
      echo " "
      echo "./$package [options] [arguments]"
      echo " "
      echo "options:"
      echo "-h, --help                              show brief help"
      echo "-n, --container-name=CONTAINER-NAME     specify name of the Mina daemon container, default: mina"
      echo "-t, --timezone=TIMEZONE                 specify time zone for the log time, default: Asia/Ho_Chi_Minh"
      echo "-a, --snark-address=ADDRESS             specify snark worker address"
      echo "-f, --snark-fee=FEE                     specify snark worker fee, default: 0.001 mina"
      echo "-d, --disable-snark-worker=TRUE/FALSE   disable/enable snark worker, default: FALSE"
      exit 0
      ;;
    -n)
      shift
        CONTAINER_NAME=$1
      shift
      ;;
    --container-name*)
        CONTAINER_NAME=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -t)
      shift
        TIMEZONE=$1
      shift
      ;;
    --timezone*)
        TIMEZONE=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -d)
      shift
        DISABLESNARKWORKER=$1
      shift
      ;;
    --disable-snark-worker*)
        DISABLESNARKWORKER=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -f)
      shift
        FEE=$1
      shift
      ;;
    --snark-fee*)
        FEE=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -a)
      shift
        SW_ADDRESS=$1
      shift
      ;;
    --snark-address*)
        SW_ADDRESS=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    *)
      break
      ;;
  esac
done

GRAPHQL_URI="$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_NAME)"
if [[ "$GRAPHQL_URI" != "" ]]; then
  GRAPHQL_URI="http://$GRAPHQL_URI:3085/graphql"
fi

if [[ "$GRAPHQL_URI" == "" ]]; then
    echo "./$package - attempt to monitor the mina daemon"
    echo " "
    echo "./$package [options] [arguments]"
    echo " "
    echo "options:"
    echo "-h, --help                              show brief help"
    echo "-n, --container-name=CONTAINER-NAME     specify name of the Mina daemon container, default: mina"
    echo "-t, --timezone=TIMEZONE                 specify time zone for the log time, default: Asia/Ho_Chi_Minh"
    echo "-a, --snark-address=ADDRESS             specify snark worker address"
    echo "-f, --snark-fee=FEE                     specify snark worker fee, default: 0.001 mina"
    echo "-d, --disable-snark-worker=TRUE/FALSE   disable/enable snark worker, default: FALSE"
    exit 0
else
  echo "GraphQL endpoint: $GRAPHQL_URI"
  while :; do
    MINA_STATUS=$(curl $GRAPHQL_URI -s --max-time 60 \
    -H 'content-type: application/json' \
    --data-raw '{"operationName":null,"variables":{},"query":"{\n  daemonStatus {\n    syncStatus\n    highestBlockLengthReceived\n    highestUnvalidatedBlockLengthReceived\n    nextBlockProduction {\n      times {\n        startTime\n      }\n    }\n  }\n}\n"}' \
    --compressed)

    LOGTIME=$(TZ=$TIMEZONE date +'(%Y-%m-%d %H:%M:%S)')
    echo $LOGTIME

    if [[ "$MINA_STATUS" == "" ]]; then
      echo "Cannot connect to the GraphQL endpoint $GRAPHQL_URI."
      sleep 10s
      continue
    fi

    STAT="$(echo $MINA_STATUS | jq .data.daemonStatus.syncStatus)"
    NEXTPROP="$(echo $MINA_STATUS | jq .data.daemonStatus.nextBlockProduction.times[0].startTime)"
    HIGHESTBLOCK="$(echo $MINA_STATUS | jq .data.daemonStatus.highestBlockLengthReceived)"
    HIGHESTUNVALIDATEDBLOCK="$(echo $MINA_STATUS | jq .data.daemonStatus.highestUnvalidatedBlockLengthReceived)"
    ARCHIVERUNNING=`ps -A | grep coda-archive | wc -l`

    # Calculate whether block producer will run within the next 5 mins
    # If up for a block within 10 mins, stop snarking, resume on next pass
    if [[ "$DISABLESNARKWORKER" == "FALSE" ]]; then
      if [[ $NEXTPROP != null ]]; then
        NEXTPROP=$(echo $NEXTPROP | jq tonumber)
        NEXTPROP="${NEXTPROP::-3}"
        NOW="$(date +%s)"
        TIMEBEFORENEXT="$(($NEXTPROP - $NOW))"
        TIMEBEFORENEXTMIN="$(($TIMEBEFORENEXT / $SECONDS_PER_MINUTE))"

        MINS="$(($TIMEBEFORENEXTMIN % $MINUTES_PER_HOUR))"
        HOURS="$(($TIMEBEFORENEXTMIN / $MINUTES_PER_HOUR))"
        DAYS="$(($HOURS / $HOURS_PER_DAY))"
        HOURS="$(($HOURS % $HOURS_PER_DAY))"
        echo "Next block production: $DAYS days $HOURS hours $MINS minutes left"

        if [[ "$TIMEBEFORENEXTMIN" -lt 10 && "$SNARKWORKERTURNEDOFF" -eq 0 ]]; then
          echo "Stopping the snark worker.."
          docker exec -t mina mina client set-snark-worker
          ((SNARKWORKERTURNEDOFF++))
        elif [[ "$TIMEBEFORENEXTMIN" -ge 10 && "$SNARKWORKERTURNEDOFF" -gt 0 ]]; then
            docker exec -t mina mina client set-snark-worker --address $SW_ADDRESS
            docker exec -t mina mina client set-snark-work-fee $FEE
            SNARKWORKERTURNEDOFF=0
        fi
      else
        echo "You haven't won any slot in the current epoch, wait for the next epoch."
        if [[ "$SNARKWORKERTURNEDOFF" -gt 0 ]]; then
          docker exec -t mina mina client set-snark-worker --address $SW_ADDRESS
          docker exec -t mina mina client set-snark-work-fee $FEE
          SNARKWORKERTURNEDOFF=0
        fi
      fi
    fi

    # Calculate difference between validated and unvalidated blocks
    # If block height is more than 10 block behind, somthing is likely wrong
    DELTAVALIDATED="$(($HIGHESTUNVALIDATEDBLOCK-$HIGHESTBLOCK))"
    echo "DELTA VALIDATE: $DELTAVALIDATED"
    if [[ "$DELTAVALIDATED" -gt 10 ]]; then
      echo "Node stuck validated block height delta more than 10 blocks"
      ((TOTALSTUCK++))
      docker restart mina
    fi

    if [[ "$STAT" == "\"SYNCED\"" ]]; then
      OFFLINECOUNT=0
      CONNECTINGCOUNT=0
    fi

    if [[ "$STAT" == "\"CONNECTING\"" ]]; then
      ((CONNECTINGCOUNT++))
      ((TOTALCONNECTINGCOUNT++))
    fi

    if [[ "$STAT" == "\"OFFLINE\"" ]]; then
      ((OFFLINECOUNT++))
      ((TOTALOFFLINECOUNT++))
    fi

    if [[ "$CONNECTINGCOUNT" -gt 1 ]]; then
      docker restart mina
      CONNECTINGCOUNT=0
    fi

    if [[ "$OFFLINECOUNT" -gt 3 ]]; then
      docker restart mina
      OFFLINECOUNT=0
    fi

    if [[ "$ARCHIVERUNNING" -gt 0 ]]; then
      ARCHIVERRUNNING=0
    else
      ((ARCHIVEDOWNCOUNT++))
    fi
    echo "Status:" $STAT, "Connecting Count, Total:" $CONNECTINGCOUNT $TOTALCONNECTINGCOUNT, "Offline Count, Total:" $OFFLINECOUNT $TOTALOFFLINECOUNT, "Archive Down Count:" $ARCHIVEDOWNCOUNT, "Node Stuck Below Tip:" $TOTALSTUCK
    sleep 300s
    test $? -gt 128 && break;
  done
fi
