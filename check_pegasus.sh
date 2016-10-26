#!/bin/bash
#
# check_pegasus.sh
# Author: Adam Barnett <ab@dneg.com>
#
# Nagios plugin to check the status of a pegasus promise raid on OSX
#

# Variables
pass=true
results=""

# Create temp files
results_tmp=`mktemp "/tmp/$$_results.XXXX"`
line_tmp=`mktemp "/tmp/$$_line.XXXX"`

# Output exit codes
function f_ok {
    echo "OK: "${1}
    exit 0
}

function f_cri {
    echo "CRITICAL: ${1}"
    exit 2
}

# Get status of the disks stripping off the headers 
`/usr/local/bin/promiseutil -C phydrv| grep -e 1 > $results_tmp`

# Check each line of the output the test results.
while read -r line; do
    if grep '^[0-9]' <<< "$line" | grep -Eqv 'OK|Media'; then
        results=$results"degraded raid: $line"
        echo $line > $line_tmp
        pass=false
    elif grep -Fx  '^No physical drive in the enclosure$'; then
        # Error when cannot find any physical drives
        echo $line > $line_tmp
        pass=false
    fi
done < $results_tmp

IFS=''
if [ $pass = false ]; then
    f_cri `cat $line_tmp`
else
    f_ok "OK"
fi

rm $results_tmp $line_tmp
