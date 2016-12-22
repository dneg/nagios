#!/usr/bin/perl
#
# Check Jenkins Executors
# ===
#
# Get executor status from Jenkins web api
#
#   Author: cyb, December 2016
#

use strict;
use warnings;
use LWP::Simple;
use JSON;
use Nagios::Plugin;

my $n = Nagios::Plugin->new(
    version => '1.00',
    shortname => "check_jenkins_executors",
    blurb => "check jenkins executor status as reported by the JSON api",
    usage => "Usage: %s -j jenkins_host",
);

$n->add_arg(
	spec => "jenkins|j=s",
	help => "-j, --jenkins=HOSTNAME. Jenkins host to query"
);

$n->getopts;

my $jenkins_host = $n->opts->jenkins;
my $jenkins_url = "http://$jenkins_host/computer/api/json";
my $downhosts = "";

# http get jenkins json exec status, decode
my $status = get($jenkins_url) or $n->nagios_die("cannot get Jenkins executor status: $jenkins_url");
my $status_json = decode_json($status);

# get ones that are offline (but not temp offline)
foreach my $executor (@{$status_json->{'computer'}}) {
  if($executor->{'offline'} and !($executor->{'temporarilyOffline'})){
   $downhosts = $downhosts."$executor->{'displayName'}:\n\t$executor->{'offlineCauseReason'}\n";
  }
}

if($downhosts){
  $n->nagios_exit(CRITICAL, sprintf("\n%s", $downhosts));
}

$n->nagios_exit(OK, sprintf('no hosts offline'));

