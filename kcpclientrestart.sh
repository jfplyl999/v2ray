#!/bin/sh
    ps -ef|grep kcptun|grep -v grep|cut -c 9-15|xargs kill -9
    ps -ef|grep udp2raw|grep -v grep|cut -c 9-15|xargs kill -9
    sleep 3
    nohup ./run.sh ./udp2raw_amd64 -c -r 255.255.255.255:8088 -l0.0.0.0:9090 --raw-mode faketcp --cipher-mode none -a -k "atrandys" >udp2raw.log 2>&1 &
    nohup ./run.sh ./client_linux_amd64 -c ./kcptun_client.json >kcptun.log 2>&1 &
    sleep 3
    ps -ef|grep kcptun && ps -ef|grep udp2ra
