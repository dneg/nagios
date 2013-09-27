#!/usr/bin/perl
#
# check_avere.pl
# Author: James Braid <jb@dneg.com>
# Checks the status of Avere FXT clusters
#

use strict;
use Nagios::Plugin;
use Data::Dumper;
use RPC::XML::Client;
use MIME::Base64;

my $n = Nagios::Plugin->new(
    shortname   => 'avere',
    usage       => 'Usage: %s --hostname HOSTNAME',
);

$n->add_arg(
    spec => 'hostname|H=s',
    help => '--hostname=HOSTNAME - hostname of the RAID controller',
);

$n->add_arg(
    spec    => 'username|u=s',
    help    => '--username=USERNAME - username for XML-RPC login',
    default => 'admin',
);

$n->add_arg(
    spec    => 'password|p=s',
    help    => '--password=PASSWORD - password for XML-RPC login',
    default => 'password',
);


$n->getopts;
$n->nagios_die("no hostname specified") unless $n->opts->hostname;

check_health();

$n->nagios_exit($n->check_messages(join_all => "\n"));

# check status via XML-RPC
sub check_health {

    my $url = sprintf "http://%s/cgi-bin/rpc2.py", $n->opts->hostname;
    my $cli = RPC::XML::Client->new($url);
    $cli->useragent()->cookie_jar({});

    my $resp = $cli->send_request('system.login', encode_base64($n->opts->username), encode_base64($n->opts->password));

    $n->nagios_die("login failed") if ($resp->value() ne 'success');

    my $alerts = $cli->simple_request('alert.events');
    if (@$alerts) {
        $n->add_message(CRITICAL, 'alerts');
        $n->add_message(OK, "\n\n");
        $n->add_message(OK, join "\n", @$alerts);
    }
}


