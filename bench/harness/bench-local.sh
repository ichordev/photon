#!/bin/bash
if [ $# -lt 3 ] ; then
    echo "Usage: RANGE RUNS NAME <server run args>"
    exit 1
fi
RANGE=$1
RUNS=$2
NAME=$3
shift 2
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
