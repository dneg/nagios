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

run_nfsping();
$n->nagios_exit($n->check_messages(join_all => "\n"));

sub run_nfsping {
  $nfsping = $nfsping . " -T" if $n->opts->get('use-tcp');
  my $cmd = sprintf "%s -q -c %s -t %s %s", $nfsping, $n->opts->count, $n->opts->time, $n->opts->hostname;
  my @output = `$cmd 2>&1`;
  chomp @output;
  my $searchstring = quotemeta "xmt/rcv/%loss";
  foreach my $line (@output) {
    # normal output
    # filer1 : xmt/rcv/%loss = 5/5/0%, min/avg/max = 0.14/0.18/0.19
    if ($line =~ /$searchstring/) {
      $line =~ s/.*$searchstring = (.*)%.*/$1/;
      my ($xmt, $rcv, $loss) = split(/\//, $line);
      $n->add_message(CRITICAL, "nfsping loss $loss% above critical threshold 100%") if ($loss >= $n->opts->critical);
    }
    # in TCP mode, server hard down
    # clnttcp_create: RPC: Remote system error - Connection timed out
    $n->add_message(CRITICAL, "host is dead") if ($line =~ /clnttcp_create: RPC: Remote system error - Connection timed out/);
  }
}

