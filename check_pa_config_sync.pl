#!/usr/bin/env perl
#
# check_pa_config_sync.pl
# Author: Danny Ling <afl@dneg.asia>
# Check Palo Alto High Availability running config synchronization status
#
use strict;
use warnings;
use XML::Simple;
use LWP::Simple;
use URI::Escape;
use Nagios::Plugin;

my $n = Nagios::Plugin->new(
  shortname => 'check_pa_config_sync',
  usage     => 'Usage: %s --hostname HOSTNAME --key KEY'
);

$n->add_arg(
  spec      => 'hostname|h=s',
  help      => '--hostname HOSTNAME - hostname of the Palo Alto Device in High Availability Pair',
  required  => 1
);

$n->add_arg(
  spec      => 'key|k=s',
  help      => '--key KEY - Palo Alto PAN-OS XML API key generated',
  required  => 1
);

$n->getopts;
# both hostname and api key are compulsory
$n->nagios_die("no hostname specified") unless $n->opts->hostname;
$n->nagios_die("no api key specified") unless $n->opts->key;

run_sync_status_check();
$n->nagios_exit(OK, "");

sub run_sync_status_check {
    my $palo_alto = $n->opts->hostname;
    my $api_key = $n->opts->key;

    # construct palo alto xml api request url
    my $url = sprintf("https://%s/api/?type=op&key=%s&cmd=%s", $palo_alto, $api_key, uri_escape("<show><high-availability><state></state></high-availability></show>"));

    # get XML output from palo alto xml api request
    my $resp = get($url);
    $n->nagios_exit(CRITICAL, "No results returned from palo altos. Is the host dead? Wrong API key?") unless defined $resp;

    my $states = XMLin($resp);
    $n->nagios_exit(CRITICAL, "XML parsing failed") unless exists $states->{"result"}; 
    
    # check running sync config status in xml format
    my $sync_status = $states->{"result"}->{"group"}->{"running-sync"};
    $n->nagios_exit(CRITICAL, "Running-sync status on $palo_alto is not synchronized.") unless ($sync_status eq "synchronized");

}
