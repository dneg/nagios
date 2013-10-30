#!/usr/bin/perl

# check_mounts.pl
# Author: Johan van den Dorpe <jvd@dneg.com>
# Identify hung mounts and other NFS problems

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use IO::CaptureOutput qw/capture_exec/;

my $timeout_cmd   = '/usr/bin/timeout -s 9';
my $timeout_secs  = 30;

GetOptions ("timeout|t=s"  => \$timeout_secs);

# Capture df output
my @check = `$timeout_cmd $timeout_secs df -P 2>&1`;
my $result = $?;

# timeout on df - use strace to find the culprit
if ($result > 1) {

  my $cmd = "$timeout_cmd $timeout_secs strace df -P";
  my ($stdout, $stderr, $success, $exit_code) = capture_exec($cmd);

  # strace output is in stderr - grab last line
  my @straceline = split /\n/, $stderr;
  my $mount = $straceline[-1];

  # strace output should look like: statfs("/hosts/nfs7",  <unfinished ...>
  if ($mount =~ /^statfs/) {
    $mount =~ s/.*\"(.*)\".*/$1/;
    critical("Hung mount on $mount");
  }
}

# Check for errors in df output
foreach my $line (@check) {

  chomp $line;

  # Ignore these: df: `/root/.gvfs': Permission denied
  next if ($line =~ /Permission denied/);

  # Case like: `/hosts/coffee/user_data2': Stale NFS file handle
  $line =~ s/[`,']//g;
  critical($line) if ($line =~ /^df: /);
}

print "OK\n";
exit 0;

sub critical {
  my $msg = shift;
  print "CRITICAL: $msg\n";
  exit 2;
}
