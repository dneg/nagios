#!/usr/bin/perl
#
# check_snmp_alive
# Author: Johan van den Dorpe <jvd@dneg.com>
#
# Nagios plugin to check SNMP responding
#

use strict;
use warnings;
use Nagios::Plugin;
use SNMP;
use Data::Dumper;

my $n = Nagios::Plugin->new(
    version => '1.00',
    shortname => "check_snmp_alive",
    blurb => "check_snmp_alive checks SNMP alive on host",
    usage => "Usage: %s -H -T",
);

$n->add_arg(
    spec => "hostname|H=s",
    help => "-H, --hostname=HOSTNAME. Hostname of the RAID array"
);

$n->getopts;

my $hostname = $n->opts->hostname;
$n->nagios_die("no hostname specified") unless $hostname;

my $status = OK;

my $sess = SNMP::Session->new( DestHost => $hostname, Version => '2', Timeout => '500000');
my $val = $sess->get('sysDescr.0');
$n->nagios_die("failed to initiate SNMP session", 2) unless $val;

$n->nagios_exit($status, $val);
