#!/bin/sh

sync
echo 3 > /proc/sys/vm/drop_caches
echo "Cache flushed on " $(hostname)
#echo 'syncronized' > tmp/ori-temp1.1.0/syncValidation.txt
