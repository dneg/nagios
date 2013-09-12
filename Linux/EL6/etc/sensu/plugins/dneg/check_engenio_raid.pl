#!/usr/bin/perl
#
# check_engenio_raid.pl
# Author: James Braid <jb@dneg.com>
# Checks the status of any LSI/Engenio/NetApp E-Series disk arrays
# Requires SMcli to be installed
#

# sudo hostsdo -el6 'yum -q -y install perl-Nagios-Plugin'
# http://www.raidinc.com/assets/Manual/Xanadu%20LSI/linux/Documentation/SANtricity%20Documentation/SANtricity%20CLI%20Guide%2010.70_RevA.pdf

use strict;
use Nagios::Plugin;
use Data::Dumper;

# paths to SMcli, we are going to try them all in order until we find one
my @sm_cli = qw(/opt/SMgr/client/SMcli /opt/dell/mdstoragesoftware/mdstoragemanager/client/SMcli /opt/dell/mdstoragesoftware/client/SMcli);

my $n = Nagios::Plugin->new(
    shortname   => 'engenio_raid',
    usage       => 'Usage: %s --hostname HOSTNAME',
);

$n->add_arg(
    spec => 'hostname|H=s',
    help => '--hostname=HOSTNAME - hostname of the RAID controller',
);

$n->getopts;
$n->nagios_die("no hostname specified") unless $n->opts->hostname;

check_health();

$n->nagios_exit($n->check_messages);

# Storage array health status = optimal.

# Storage array health status = fixing.                                     
# The following failures have been found:
# Failed physical disk
# Storage array: nfs5raid1
# Component reporting problem: Physical Disk in slot 1
#   Status: Failed
#   Location: RAID enclosure 0, Drawer 1
# Component requiring service: Physical Disk in slot 1
#   Service action (removal) allowed: Yes
#   Service action LED on component: Yes
# 
# Degraded Virtual Disk
# Storage array: nfs5raid1
#   Disk group: 1
#     RAID level: 6
#     Status: Degraded
#       Enclosure: RAID enclosure 0, Drawer 1
#         Affected physical disk slot(s): 1
#           Service action (removal) allowed: Yes
#           Service action LED on component: Yes
#     Virtual Disks: 1

# The following failures have been found:
# Volume - Hot Spare In Use
# Storage array: Lead_R2_0637018811
# Volume group: 4
#   Failed drive at: tray 1, slot 1
#     Service action (removal) allowed: No
#     Service action LED on component: No
#   Replaced by drive at: tray 1, slot 16
#   Volumes: FIBRE_61_E7_A3
#     RAID level: 5
#     Status: Optimal
# 
# Impending Drive Failure - Medium Data Availability Risk
# Storage array: Lead_R2_0637018811
# Volume group: 5
#   RAID level: 5
#   Tray: Drive tray 1
#     Affected drive slot(s): 6
#     Service action (removal) allowed: No
#     Service action LED on component: Yes
#   Volumes: FIBRE_61_E9_B2
#     Status: Optimal
# 
# Bypassed Drive
# Storage array: Lead_R2_0637018811
# Component reporting problem: Drive in slot 1
#   Status: Unknown
#   Location: Drive tray 1
# Component requiring service: Drive in slot 1
#   Bypassed by: Drive in tray 1, slot 1
#   Service action (removal) allowed: No
#   Service action LED on component: Yes
sub check_health {

    my @output = run_sm_cli($n->opts->hostname, "show storageArray healthStatus;");

    # expecting exactly one line which contains
    # Storage array health status = optimal.
    #
    if (grep { /^Storage array health status = optimal.$/ } @output) {
        $n->add_message(OK, 'storage array is optimal');

        # now make sure we have exactly one line
        if (scalar @output != 1) {
            $n->add_message(WARNING, 'storage array is optimal but we also got a message');
            $n->add_message(WARNING, @output);
        }
    }

    # otherwise we are fixing
    elsif (grep { /^Storage array health status = fixing.$/ } @output) {
        $n->add_message(WARNING, 'storage array is repairing - ');

        if (grep { /^Failed physical disk$/ } @output) {
            $n->add_message(WARNING, 'failed disk');
        }
        if (grep { /^Degraded virtual disk$/ } @output) {
            $n->add_message(WARNING, 'degraded volume');
        }

#         } else {
#             $n->add_message(WARNING, 'unknown component');
#         }
    }

    # fall through to failures - doesn't appear to be a health status = failed. line
    elsif (grep { /^The following failures have been found/ } @output) {
        $n->add_message(CRITICAL, 'storage array has failures');
        print Dumper @output;
        if (grep { /^Volume - Hot Spare In Use/ } @output) {
            $n->add_message(CRITICAL, 'hot spare in use');
        }
        if (grep { /^Impending Drive Failure/ } @output) {
            $n->add_message(CRITICAL, 'impending drive failure');
        }
        if (grep { /^Bypassed Drive/ } @output) {
            $n->add_message(CRITICAL, 'bypassed drive');
        }
        if (grep { /^Disk Pool Capacity - Warning Threshold Exceeded/ } @output) {
            $n->add_message(CRITICAL, 'disk pool capacity');
        }
        if (grep { /^Individual Drive - Degraded Path/ } @output) {
            $n->add_message(CRITICAL, 'degraded drive path');
        }
        
    }


    # or unknown
    else {
        $n->add_message(WARNING, 'storage array is in an unknown state');
        $n->add_message(WARNING, @output);
    }

}


# run a command on a disk array
sub run_sm_cli {
    my $hostname = shift;
    my $command = shift;
    my $sm_cli = find_sm_cli();

    # -S = supress informational messages (parsing command, running command, command success, etc)
    my $cmd = sprintf '%s %s -S -c "%s"', $sm_cli, $hostname, $command;
    #print "running $cmd\n";
    my @lines = split /\n/, `$cmd`;

    my $ret = ($? >> 8);
    $n->nagios_die("SMcli execution failed for command [$command] - syntax error?") unless ($ret == 0);

    return @lines;
}

# find SMcli binary in a few paths
sub find_sm_cli {
    my $sm_cli;
    foreach my $path (@sm_cli) {
        next unless (-e $path);
        next unless (-x $path);
        $sm_cli = $path;
    }

    $n->nagios_die("SMcli missing or not executable (tried @sm_cli)") unless ($sm_cli);
    return $sm_cli;
}

