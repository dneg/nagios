#!/bin/bash

# Get current status of cache 
CURRENT_CACHE_SIZE=`/opt/dell/srvadmin/bin/omreport storage nvmeadapter controller=3 |awk -F'[ %]' '/^Remaining Rated Write Endurance/ {print $6}'`
CRITICAL=25

if [[ $CURRENT_CACHE_SIZE -le $CRITICAL ]]; then
  STATUS="CRITICAL - Cache is under $CRITICAL%"
  EXIT=2
else
  STATUS="Ok - Move along, nothing to see here"
  EXIT=0
fi

# Print status and exit
echo $STATUS
exit $EXIT

