#!/bin/bash
if [ $# -lt 3 ] ; then
    echo "Usage: RANGE RUNS NAME <server run args>"
    echo "Example: ./bench-local 10-1k:10 10x3 photon ./hello-photon"
    echo "Means in range of 10 - 1000 connections, step 10"
    echo "10 seconds per run, with summary of 3 runs"
    exit 1
fi
RANGE=$1
RUNS=$2
NAME=$3
shift 3
rusage 0.05:$NAME-res.csv "$@" &
SERV=$!
sleep 1
http_load $RANGE $RUNS 127.0.0.1:8080 > $NAME-http.csv &
HTTP=$!
tail -F $NAME-http.csv &
TAIL=$!
wait $HTTP
kill -INT $SERV
kill -INT $TAIL
