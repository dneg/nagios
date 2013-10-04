#!/usr/bin/perl
#
# check_engenio_raid_perf.pl
# Author: James Braid <jb@dneg.com>
# Outputs performance data for LSI/Engenio/NetApp E-Series disk arrays
# Requires SMcli to be installed
#

use strict;
use Nagios::Plugin;
use Data::Dumper;
use File::Slurp qw(read_file);
use lib qw(/tools/SITE/perl);
use dnutil qw(dnsite_sg);
use Text::CSV;

# paths to SMcli, we are going to try them all in order until we find one
my @sm_cli = qw(/opt/SMgr/client/SMcli /opt/dell/mdstoragesoftware/mdstoragemanager/client/SMcli /opt/dell/mdstoragemanager/client/SMcli);

my $n = Nagios::Plugin->new(
    shortname   => 'engenio_raid_perf',
    usage       => 'Usage: %s --hostname HOSTNAME',
);

$n->add_arg(
    spec => 'hostname|H=s',
    help => '--hostname=HOSTNAME - hostname of the RAID controller',
);

$n->getopts;
$n->nagios_die("no hostname specified") unless $n->opts->hostname;

my @output = run_sm_cli($n->opts->hostname, "set session performanceMonitorInterval=10 performanceMonitorIterations=1; show allVirtualDisks performanceStats;");
#my @output = read_file('stats.txt');

# skip non csv and blank lines
@output = grep { /,/ } grep { !/^$/ } @output;

# parse the csv output into a hash
my @results;
my $csv = Text::CSV->new();

$csv->parse(shift @output);
my @names = $csv->fields();

foreach my $line (@output) {
    $csv->parse($line);
    my %hash;
    @hash{@names} = $csv->fields();
    push @results, \%hash;
}

my $timestamp = time();

my $prefix = (dnsite_sg() ? 'asia.dneg' : 'com.dneg');

# format the stats
foreach my $chunk (@results) {
    foreach my $key (keys %$chunk) {
        next if ($chunk->{'Storage Arrays '} =~ /Capture Iteration|Date\/Time/);
        next if ($key =~ /Storage Arrays/);

        # thing is controller, vdisk, array, etc
        my $thing = thing_map($chunk->{'Storage Arrays '});
        # tidy_key is the name of the statistic
        my $tidy_key = stat_map($key);

        my $path = sprintf "%s.%s.%s.%s", $prefix, $n->opts->hostname, $thing, $tidy_key;
        my $value = $chunk->{$key};
        $n->nagios_die("$path still has spaces - failing") if ($path  =~ /\s+/);

        print "$path $value $timestamp\n";

    }
}

# tidy up the array/vdisk/etc names
sub thing_map {
    my $thing = shift;
    $thing =~ s/^STORAGE ARRAY TOTALS$/array/g;
    $thing =~ s/^CONTROLLER IN SLOT (\d+)$/ctrl$1/g;
    $thing =~ s/^Virtual Disk (\d+)$/vdisk$1/g;
    return $thing;
}

# tidy up the stats names
sub stat_map { 
    my $tidy_key = shift;
    $tidy_key =~ s/\s+$//g;
    $tidy_key =~ s/\s+/_/g;
    $tidy_key =~ s/\//_/g;
    $tidy_key =~ s/%/pct/g;
    $tidy_key = lc $tidy_key;
    return $tidy_key;
}


# run a command on a disk array
sub run_sm_cli {
    my $hostname = shift;
    my $command = shift;
    my $sm_cli = find_sm_cli();

    # we need to connect to both controllers
    my $controllers = sprintf "%sa %sb", $hostname, $hostname;

    # -S = supress informational messages (parsing command, running command, command success, etc)
    my $cmd = sprintf '%s %s -S -c "%s"', $sm_cli, $controllers, $command;
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

