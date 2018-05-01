#!/bin/bash -xe
if [ $# -lt 3 ] ; then
    echo "Usage: RANGE RUNS SERVER-HOST SERVER-HOST-LOCAL CLIENT-HOST NAME <server run args>"
    echo "Example: ./bench-local 10-1k:10 10x3 localhost localhost localhost photon ./hello-photon"
    echo "Means in range of 10 - 1000 connections, step 10"
    echo "10 seconds per run, with summary of 3 runs"
    exit 1
fi
RANGE=$1
RUNS=$2
SERVNODE=$3
SERVNODELOCAL=$4
CLIENTNODE=$5
NAME=$6
shift 6

ssh $SERVNODE ./unlimited.sh rusage 0.05:$NAME-res.csv "$@" &
SERV=$!
sleep 1
ssh $CLIENTNODE ./unlimited.sh http_load $RANGE $RUNS http://$SERVNODELOCAL:8080 > $NAME-http.csv &
HTTP=$!
wait $HTTP
kill -INT $SERV
rsync $SERVNODE:$NAME-res.csv
wait