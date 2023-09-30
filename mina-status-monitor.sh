#!/bin/bash
MINA_STATUS=""
STAT=""
CONNECTINGCOUNT=0
OFFLINECOUNT=0
CATCHUPCOUNT=0
TOTALCONNECTINGCOUNT=0
TOTALOFFLINECOUNT=0
TOTALSTUCKCOUNT=0
TOTALCATCHUPCOUNT=0
TOTALHEIGHTOFFCOUNT=0
TIMEZONE=Asia/Ho_Chi_Minh
SNARKWORKERTURNEDOFF=1 ### assume snark worker not turned on for the first run
DISABLESNARKWORKER=TRUE ### disable/enable snark worker
SNARKWORKERSTOPPEDCOUNT=0
readonly SECONDS_PER_MINUTE=60
readonly MINUTES_PER_HOUR=60
readonly HOURS_PER_DAY=24
readonly SECONDS_PER_HOUR=3600
FEE=0.001 ### SET YOUR SNARK WORKER FEE HERE ###
SW_ADDRESS= ### SET YOUR SNARK WORKER ADDRESS HERE ###
GRAPHQL_URI=""
NEXTPROP=null
UPTIMESECS=0
BCLENGTH=0
HIGHESTBLOCK=0
HIGHESTUNVALIDATEDBLOCK=0
SIDECARREPORTING=0
SYNCCOUNT=0
DISABLESIDECAR=FALSE ### disable/enable mina-sidecar monitor
DISABLE_EXTERNAL_IP=TRUE ### disable/enable external ip monitor
EXTERNAL_IP=$(curl -s http://whatismyip.akamai.com)

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
      echo "-t, --timezone=TIMEZONE                 specify time zone for the log time, default: Asia/Ho_Chi_Minh"
      echo "-a, --snark-address=ADDRESS             specify snark worker address"
      echo "-f, --snark-fee=FEE                     specify snark worker fee, default: 0.001 mina"
      echo "-sw, --disable-snark-worker=TRUE/FALSE  disable/enable snark worker stopper, default: TRUE"
      echo "-sc, --disable-sidecar=TRUE/FALSE       disable/enable sidecar monitor, default: FALSE"
      echo "-eip, --disable-external-ip=TRUE/FALSE  disable/enable external ip monitor, default: TRUE"
      exit 0
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
    -sw)
      shift
        DISABLESNARKWORKER=$1
      shift
      ;;
    --disable-snark-worker*)
        DISABLESNARKWORKER=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -sc)
      shift
        DISABLESIDECAR=$1
      shift
      ;;
    --disable-sidecar*)
        DISABLESIDECAR=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -eip)
      shift
        DISABLE_EXTERNAL_IP=$1
      shift
      ;;
    --disable-external-ip*)
        DISABLE_EXTERNAL_IP=`echo $1 | sed -e 's/^[^=]*=//g'`
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

GRAPHQL_URI="$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mina)"
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
    echo "-t, --timezone=TIMEZONE                 specify time zone for the log time, default: Asia/Ho_Chi_Minh"
    echo "-a, --snark-address=ADDRESS             specify snark worker address"
    echo "-f, --snark-fee=FEE                     specify snark worker fee, default: 0.001 mina"
    echo "-sw, --disable-snark-worker=TRUE/FALSE  disable/enable snark worker stopper, default: FALSE"
    echo "-sc, --disable-sidecar=TRUE/FALSE       disable/enable sidecar monitor, default: FALSE"
    exit 0
else
  echo "GraphQL endpoint: $GRAPHQL_URI"
  echo "Disable snark worker stopper: $DISABLESNARKWORKER"
  echo "Disable sidecar monitor: $DISABLESIDECAR"
  while :; do
    MINA_STATUS=$(curl $GRAPHQL_URI -s --max-time 60 \
    -H 'content-type: application/json' \
    --data-raw '{"operationName":null,"variables":{},"query":"{\n  daemonStatus {\n    syncStatus\n    uptimeSecs\n    blockchainLength\n    highestBlockLengthReceived\n    highestUnvalidatedBlockLengthReceived\n    nextBlockProduction {\n      times {\n        startTime\n      }\n    }\n  }\n}\n"}' \
    --compressed)

    LOGTIME=$(TZ=$TIMEZONE date +'(%Y-%m-%d %H:%M:%S)')
    echo $LOGTIME

    if [[ "$MINA_STATUS" == "" ]]; then
      echo "Cannot connect to the GraphQL endpoint $GRAPHQL_URI."
      sleep 3s
      continue
    fi

    STAT="$(echo $MINA_STATUS | jq .data.daemonStatus.syncStatus)"
    NEXTPROP="$(echo $MINA_STATUS | jq .data.daemonStatus.nextBlockProduction.times[0].startTime)"
    UPTIMESECS="$(echo $MINA_STATUS | jq .data.daemonStatus.uptimeSecs)"
    BCLENGTH="$(echo $MINA_STATUS | jq .data.daemonStatus.blockchainLength)"
    HIGHESTBLOCK="$(echo $MINA_STATUS | jq .data.daemonStatus.highestBlockLengthReceived)"
    HIGHESTUNVALIDATEDBLOCK="$(echo $MINA_STATUS | jq .data.daemonStatus.highestUnvalidatedBlockLengthReceived)"
    SIDECARREPORTING="$(docker logs --since 10m mina-sidecar 2>&1 | grep -c 'Got block data')"

    # Calculate whether block producer will run within the next 10 mins
    # If up for a block within 10 mins, stop snarking, resume on next pass
    if [[ "$DISABLESNARKWORKER" == "FALSE" && "$STAT" == "\"SYNCED\"" ]]; then
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
              echo "Starting the snark worker.."
              docker exec -t mina mina client set-snark-worker --address $SW_ADDRESS
              docker exec -t mina mina client set-snark-work-fee $FEE
              SNARKWORKERTURNEDOFF=0
        fi
      else
        echo "You haven't won any slot in the current epoch, wait for the next epoch."
        if [[ "$SNARKWORKERTURNEDOFF" -gt 0 ]]; then
          echo "Starting the snark worker.."
          docker exec -t mina mina client set-snark-worker --address $SW_ADDRESS
          docker exec -t mina mina client set-snark-work-fee $FEE
          SNARKWORKERTURNEDOFF=0
        fi
      fi
    fi

    # Calculate difference between validated and unvalidated blocks
    # If block height is more than 5 block behind, somthing is likely wrong
    DELTAVALIDATED="$(($HIGHESTUNVALIDATEDBLOCK-$HIGHESTBLOCK))"
    echo "DELTA VALIDATE: $DELTAVALIDATED"
    if [[ "$DELTAVALIDATED" -gt 5 ]]; then
      echo "Node stuck validated block height delta more than 5 blocks."
      ((TOTALSTUCKCOUNT++))
      SYNCCOUNT=0
      docker restart mina
    fi

    if [[ "$STAT" == "\"SYNCED\"" ]]; then
      OFFLINECOUNT=0
      CONNECTINGCOUNT=0
      CATCHUPCOUNT=0
      ((SYNCCOUNT++))
    fi
    
    if [[ "$STAT" == "\"BOOTSTRAP\"" ]]; then
      SNARKWORKERTURNEDOFF=1
    fi    

    if [[ "$STAT" == "\"CONNECTING\"" ]]; then
      ((CONNECTINGCOUNT++))
      ((TOTALCONNECTINGCOUNT++))
      SYNCCOUNT=0

      EXPLORER_STATUS=$(curl 'https://api.minaexplorer.com' -s --max-time 60 \
      -H 'content-type: application/json' \
      --compressed)
      LATEST_E_BLOCK=$(echo $EXPLORER_STATUS | jq .blockchainLength)
      if [[ "$(($LATEST_E_BLOCK - $BCLENGTH))" -gt 5 ]]; then
        echo "Restarting mina - Offline state and behind the MinaExplorer more than 5 blocks"
        docker restart mina
        CONNECTINGCOUNT=0
      fi
    fi

    if [[ "$STAT" == "\"OFFLINE\"" ]]; then
      ((OFFLINECOUNT++))
      ((TOTALOFFLINECOUNT++))
      SYNCCOUNT=0

      EXPLORER_STATUS=$(curl 'https://api.minaexplorer.com' -s --max-time 60 \
      -H 'content-type: application/json' \
      --compressed)
      LATEST_E_BLOCK=$(echo $EXPLORER_STATUS | jq .blockchainLength)
      if [[ "$(($LATEST_E_BLOCK - $BCLENGTH))" -gt 5 ]]; then
        echo "Restarting mina - Offline state and behind the MinaExplorer more than 5 blocks"
        docker restart mina
        OFFLINECOUNT=0
      fi
    fi

    if [[ "$STAT" == "\"CATCHUP\"" ]]; then
      ((CATCHUPCOUNT++))
      ((TOTALCATCHUPCOUNT++))
      SYNCCOUNT=0

      # If the node is catchup for the second time, the the blockchain length is more than 5 blocks behind
      # 2 hours is enough for the node to sync
      if [[ "$(($HIGHESTBLOCK - $BCLENGTH))" -gt 5 && "$(($UPTIMESECS / $SECONDS_PER_HOUR))" -gt 2 ]]; then
        echo "Blockchain length is behind Highest block length more than 5 blocks", $BCLENGTH, $HIGHESTBLOCK, $HIGHESTUNVALIDATEDBLOCK
        ((TOTALHEIGHTOFFCOUNT++))
        docker restart mina
        CATCHUPCOUNT=0
      fi
    fi

    if [[ "$CONNECTINGCOUNT" -gt 1 ]]; then
      echo "Restarting mina - too long in Connecting state (~10 mins)"
      docker restart mina
      CONNECTINGCOUNT=0
      SYNCCOUNT=0
    fi

    if [[ "$OFFLINECOUNT" -gt 3 ]]; then
      echo "Restarting mina - too long in Offline state (~20 mins)"
      docker restart mina
      OFFLINECOUNT=0
      SYNCCOUNT=0
    fi

    if [[ "$CATCHUPCOUNT" -gt 8 ]]; then
      echo "Restarting mina - too long in Catchup state (~45 mins)"
      docker restart mina
      CATCHUPCOUNT=0
      SYNCCOUNT=0
    fi

    if [[ "$SIDECARREPORTING" -lt 3 && "$SYNCCOUNT" -gt 2 && "$DISABLESIDECAR" == "FALSE" ]]; then
      echo "Restarting mina-sidecar - only reported " $SIDECARREPORTING " times out in 10 mins and node in sync longer than 15 mins."
      docker restart mina-sidecar
    fi

    if [[ "$DISABLE_EXTERNAL_IP" == "FALSE" ]]; then
      LATEST_EXTERNAL_IP=$(curl -s http://whatismyip.akamai.com)
      if [[ "$EXTERNAL_IP" != "$LATEST_EXTERNAL_IP" ]]; then
        echo "External IP changed from $EXTERNAL_IP to $LATEST_EXTERNAL_IP."
        EXTERNAL_IP=$LATEST_EXTERNAL_IP
        docker restart mina
      fi
    fi

    echo "Status:" $STAT, "Synced Count:" $SYNCCOUNT,  "Connecting Count, Total:" $CONNECTINGCOUNT $TOTALCONNECTINGCOUNT, "Offline Count, Total:" $OFFLINECOUNT $TOTALOFFLINECOUNT, "Catchup Count, Total:" $CATCHUPCOUNT $TOTALCATCHUPCOUNT, "Total Height Mismatch:" $TOTALHEIGHTOFFCOUNT, "Node Stuck Below Tip:" $TOTALSTUCKCOUNT
    sleep 300s
    test $? -gt 128 && break;
  done
fi
