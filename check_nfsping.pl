#!/usr/bin/env perl

# check_nfsping.pl
# Author: Johan van den Dorpe <jvd@dneg.com>
# Use nfsping to check the availability of an NFS server
#
# TODO: Also test mount protocol
#       Handle hosts with multiple interfaces

use strict;
use warnings;
use Data::Dumper;
use Nagios::Plugin;
use Switch;

my $nfsping = "/usr/bin/nfsping";

my $n = Nagios::Plugin->new(
  shortname => 'check_nfsping',
  usage     => 'Usage: %s --hostname HOSTNAME'
);

$n->add_arg(
  spec      => 'hostname|H=s',
  help      => '--hostname HOSTNAME - hostname of the NFS server',
  required  => 1
);

$n->add_arg(
  spec    => 'count=s',
  help    => '--count COUNT - number of nfsping packets to send (Default: 5)',
  default => 5
);

$n->add_arg(
  spec    => 'time=s',
  help    => '--time TIMEOUT - milliseconds before ping times out (Default: 2500)',
  default => 2500
);

$n->add_arg(
  spec    => 'critical=s',
  help    => '--critical CRITICAL - critical loss percentage threshold (Default: 100)',
  default => 100 
);

$n->add_arg(
  spec => 'use-tcp|T',
  help => '--use-tcp - use TCP (Default: UDP)'
);


$n->getopts;
$n->nagios_die("no hostname specified") unless $n->opts->hostname;
$n->nagios_die("nfsping not installed") unless (-e $nfsping);

run_nfsping();
$n->nagios_exit(OK, "");

sub run_nfsping {
  $nfsping = $nfsping . " -T" if $n->opts->get('use-tcp');
  my $cmd = sprintf "%s -q -c %s -t %s %s", $nfsping, $n->opts->count, $n->opts->time, $n->opts->hostname;
  my @output = `$cmd 2>&1`;
  my $result = $?;
  chomp @output;

  # Search for known errors in output
  my $searchstring = quotemeta "xmt/rcv/%loss";
  foreach my $line (@output) {
    switch ($line) {

      # normal output
      # filer1 : xmt/rcv/%loss = 5/5/0%, min/avg/max = 0.14/0.18/0.19
      case /$searchstring/ {
        $line =~ s/.*$searchstring = (.*)%.*/$1/;
        my ($xmt, $rcv, $loss) = split(/\//, $line);
        $n->nagios_exit(CRITICAL, "nfsping loss $loss% above critical threshold 100%") if ($loss >= $n->opts->critical);
      }

      # in TCP mode, server hard down
      # clnttcp_create: RPC: Remote system error - Connection timed out
      case qr/clnttcp_create: RPC: Remote system error - Connection timed out/ { $n->nagios_exit(CRITICAL, "host is dead") }

      # server hard down
      # clnttcp_create: RPC: Remote system error - No route to host
      case qr/clnttcp_create: RPC: Remote system error - No route to host/ { $n->nagios_exit(CRITICAL, "host is dead") }

    }
  }

  # If exitcode is not 0, return UNKNOWN
  $n->nagios_exit(UNKNOWN, \@output) if ($result != 0)
}

