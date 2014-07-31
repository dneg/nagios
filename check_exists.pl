#!/usr/bin/perl
#
# check_exists
# Author: James Braid <jb@dneg.com>
#
# Nagios plugin to check for files existing
#

use strict;
use warnings;
use Nagios::Plugin;
use Data::Dumper;

my $n = Nagios::Plugin->new(
    version => '1.00',
    shortname => "check_exists",
    blurb => "check_exists checks for existence of files/directories",
    usage => "Usage: %s -H -T",
);

$n->add_arg(
    spec => "filename|f=s",
    help => "-f, --filename=FILENAME. Path name to check for existence"
);

$n->getopts;

my $filename = $n->opts->filename;
$n->nagios_die("no path specified") unless $filename;

$n->nagios_exit(OK, sprintf '%s exists', $filename) if (-e $filename);
$n->nagios_exit(CRITICAL, sprintf '%s does not exist', $filename) unless (-e $filename);
$n->nagios_exist(UNKNOWN, 'this should never happen');
