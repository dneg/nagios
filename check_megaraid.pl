#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

my $megaraid = "bash -c /apps/Linux64/bin/megasasctl";

my @output = `$megaraid 2>&1`;

if ($? ne 0) {
  unknown($output[0]);
}

foreach my $line (@output) {

  # Ensure volumes are optimal
  if ($line =~ /^a\dd/) {
    my @volume = split(/\s+/, $line);
    critical("volume $volume[0] is $volume[5]") unless ($volume[5] eq "optimal");
  }

  # Output physical disk errors
  if ($line =~ /^a\de/) {
    # skip online disk
    next if $line =~ /^a\de.*online/;
    my @disk = split(/\s+/, $line);
    critical("disk $disk[0] is $disk[2]") unless ($disk[2] eq "hotspare");
  }
}

print "Everything OK\n";
exit 0;

sub critical {
  my $message = shift;
  print "CRITICAL: $message\n";
  exit 2;
}

sub unknown {
  my $message = shift;
  print "UNKNOWN: $message\n";
  exit 3;
}
