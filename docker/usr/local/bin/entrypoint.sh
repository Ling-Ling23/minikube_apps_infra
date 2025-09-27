#!/bin/bash

TAG="$(basename $0 '.sh')"

serials=/etc/entrypoint.d/serial/*
for serial in ${serials}; do 
    echo "$TAG: running $serial"
    chmod a+rx $serial
    $serial
done

forks=/etc/entrypoint.d/fork/*
for fork in ${forks}; do 
    echo "$TAG: running $fork"
    chmod a+rx $fork
    $fork &
done

exec $@

