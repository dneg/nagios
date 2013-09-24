#!/usr/bin/perl
#
# check_infortrend
# Nagios plugin for Infortrend RAID arrays
# James Braid <jamesb@loreland.org>
#
# This plugin monitors Infortrend RAID arrays. There are a couple of different 
# MIBs which Infortrend uses. This plugin should deal with both of them.
#
# Please report any bugs or missing features to me.
#

use strict;
use warnings;
use Nagios::Plugin;
use SNMP;
use Data::Dumper;
use Bit::Vector;
use Log::Log4perl qw(:easy);
use FindBin;

# FindBin doesn't work if we are running in the embedded perl
my $mib_base = $FindBin::Bin;

my $n = Nagios::Plugin->new(
    version => '2.01',
    shortname => "infortrend",
    blurb => "check_infortrend checks Infortrend RAID arrays via SNMP",
    usage => "Usage: %s -H -T -w -c",
);

$n->add_arg(
    spec => "hostname|H=s",
    help => "-H, --hostname=HOSTNAME. Hostname of the RAID array"
);

$n->add_arg(
    spec => "debug|d",
    help => "--debug, -d"
);

$n->getopts;

my $log_level = $ERROR;
$log_level = $DEBUG if $n->opts->debug;
Log::Log4perl->easy_init($log_level);

my $hostname = $n->opts->hostname;
$n->nagios_die("no hostname specified") unless $hostname;

my $status = OK;
my $message;

my $sess = SNMP::Session->new( DestHost => $hostname, Version => '2', Timeout => '500000');
$n->nagios_die("failed to initiate SNMP session") unless $sess;

# We need to switch MIBs based on firmware version
# old location of fwVersion
my $fwVersion = '.1.3.6.1.4.1.1714.1.1.1.5.0';
#my $fwVersion = '.1.3.6.1.4.1.1714.1.1.1.1.5.0';

# Set a timeout around this - $fwVersion can be returned undefined if either the raid gives the wrong
# response or no response, so we can't work out which it is. So set our own timeout faster than
# the SNMP one to pick this up. The longer SNMP timeout is useful for the later stages where
# we load a whole table
eval {
	$SIG{ALRM} = sub { die "Timeout"; };
	alarm(20);
	$fwVersion = $sess->get($fwVersion);
	#DEBUG Dumper $fwVersion;
	alarm(0);
	if (!defined $fwVersion) {
   		$n->nagios_die("$hostname is not supported by this plugin (or SNMP is taking a long time to respond)");
	}
	if ($fwVersion eq 'NOSUCHOBJECT') {
    		DEBUG "using newer MIB";
    		&SNMP::addMibFiles($mib_base . '/IFT_MIB_v1.11G14.mib');
	} elsif ($fwVersion < 48) {
    		DEBUG "using older MIB"; 
    		&SNMP::addMibFiles($mib_base . '/IFT-SNMP-MIB.mib');
	} else {
    		$n->nagios_die("unknown RAID type/firmware");
	}
};

if ($@ && $@ =~ /Timeout/) {
	$n->nagios_die("RAID took too long to respond - it maybe be busy in I/O");
}

# hdd table = physical devices
my $hddTable = $sess->gettable('hddTable');
DEBUG Dumper $hddTable;
#          '5' => {
#                   'hddSpeed' => '10',
#                   'hddSlotNum' => '5',
#                   'hddBlkSizeIdx' => '9',
#                   'hddResvSpace' => '4094',
#                   'hddPhyChlNum' => '2',
#                   'hddLdId' => '40674BE0',
#                   'hddSerialNum' => '            5QD1',
#                   'hddFwRevStr' => 'E   ',
#                   'hddSize' => '1464614912',
#                   'hddStatus' => '1',
#                   'hddScsiId' => '4',
#                   'hddModelStr' => 'ST3750640AS             ',
#                   'hddDataWidth' => '0',
#                   'hddLogChlNum' => '0',
#                   'hddState' => '0',
#                   'hddScsiLun' => '0',
#                   'hddIndex' => '5'
#                 }
#
#    DESCRIPTION "Hard disk drive status
#                    0 : New Drive
#                    1 : On-Line Drive
#                    2 : Used Drive
#                    3 : Spare Drive
#                    4 : Drive Initialization in Progress
#                    5 : Drive Rebuild in Progress
#                    6 : Add Drive to Logical Drive in Progress
#                    9 : Global Spare Drive
#                    0x11 : Drive is in process of Cloning another Drive
#                    0x12 : Drive is a valid Clone of another Drive
#                    0x13 : Drive is in process of Copying from another Drive
#                            (for Copy/Replace LD Expansion function)
#                    0x3f : Drive Absent
#                    0x8x: SCSI Device (Type x)
#                    0xfc : Missing Global Spare Drive
#                    0xfd : Missing Spare Drive
#                    0xfe : Missing Drive
#                    0xff : Failed Drive"
#

foreach (sort keys %$hddTable) {
    my $hdd = $hddTable->{$_};

    my $slot = $hdd->{hddSlotNum};
    my $status = $hdd->{hddStatus};

    if ($hdd->{hddStatus} != 1 && # on-line
        $hdd->{hddStatus} != 3 && # spare
        $hdd->{hddStatus} != 4 && # initializing
        $hdd->{hddStatus} != 5 && # rebuild
        $hdd->{hddStatus} != 9 && # global spare
        $hdd->{hddSize} > 0) {
#        DEBUG Dumper $hdd;
        $n->add_message(CRITICAL, "Drive in slot $slot is broken");
    }
}

my $ldTable = $sess->gettable('ldTable');
DEBUG Dumper $ldTable;
foreach (sort keys %$ldTable) {
    my $ld = $ldTable->{$_};

    my $failed = $ld->{ldFailedDrvCnt};
    my $id = $ld->{ldID};
    my $status = $ld->{ldStatus};
    my $state = $ld->{ldState};

#    DESCRIPTION "Logical drive status
#                    BITS 0-2 : Status Code (RO):
#                              0 : Good
#                              1 : Rebuilding
#                              2 : Initializing
#                              3 : Degraded
#                              4 : Dead
#                              5 : Invalid
#                              6 : Incomplete
#                              7 : Drive Missing
#                    BITS 3-6 : Reserved.
#                    BITS 7 : Logical Drive Off-line (RW)."


    if ($failed > 0) {
        $n->add_message(CRITICAL, "LD $id has $failed failed drives");
    }

    # extract bits 0-2
    my $bv = Bit::Vector->new_Dec(8, $status);
    my $enum = $bv->to_Enum;
    DEBUG "ld status: $enum";
    my $status_bv = Bit::Vector->new(2);
    $status_bv->Interval_Copy($bv, 0, 1, 2);
    $status = $status_bv->to_Dec;
    DEBUG "bits 0-2: $status";

    if ($status != 0) {
        DEBUG "ldstatus is [$status]";
        $n->add_message(CRITICAL, "LD $id is broken");
    }
}

# Checking for knackered redundant controllers
#For some reason the textual version doesn't work. 
#Do an SNMP walk for redCtlrStatus with -O n to find this number
if ($fwVersion eq 'NOSUCHOBJECT') {
	# Only works on new MIB stuff
	my $controllers = $sess->get('.1.3.6.1.4.1.1714.1.1.1.6.4.0');

	# 0x3F bits being set indicates a controller failure. So this test is sufficient for the moment
	if(defined $controllers and $controllers > 32) {
		$n->add_message(CRITICAL,"Redundant Controller failure has been detected - system has failed over");
	}
DEBUG Dumper $controllers;
}

# luDev = random devices
my $luDevTable = $sess->gettable('luDevTable', noindexes => 1);
DEBUG Dumper $luDevTable;

foreach (sort keys %$luDevTable) {
    my $dev = $luDevTable->{$_};

    my $type = $dev->{luDevTypeCode};
    my $desc = $dev->{luDevDescription};

    my $status_bit = $dev->{luDevStatus};    
    my $bv = Bit::Vector->new_Dec(8, $status_bit);

#    DEBUG Dumper $bv->to_Enum;
    my $foo = $bv->to_Enum;
    DEBUG "$desc - $foo";

    if ($type == 1 || $type == 2) {
        # psu or fan - they use the same bitmaps
        $n->add_message(CRITICAL, "$desc is malfunctioning") if $bv->bit_test(0);
        $n->add_message(CRITICAL, "$desc is off") if $bv->bit_test(6);
        $n->add_message(CRITICAL, "$desc is missing") if $bv->bit_test(7);
    }

    # slot
    #if ($type == 17) {
    #    $n->add_message(CRITICAL, "$desc is marked BAD") if $bv->bit_test(1);
    #}

    if ($type == 3 || $type == 5) {
        # temperature and voltage
        my $status_bv = Bit::Vector->new(3);
        $status_bv->Interval_Copy($bv, 0, 1, 3);
        my $status = $status_bv->to_Dec;
        DEBUG "$desc is $status";

        # temp
        if ($type == 3) {
            $n->add_message(CRITICAL, "$desc is too hot") if $status == 3;
            $n->add_message(CRITICAL, "$desc is SUPER hot") if $status == 5;
        }

        # voltage
    }
}

#my $allEvtTable = $sess->gettable('allEvtTable');
#DEBUG Dumper $allEvtTable;

# luntable = 

($status, $message) = $n->check_messages(join => "; ");
$n->nagios_exit($status, $message);
