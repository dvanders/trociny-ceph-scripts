#!/usr/bin/perl -w

#
# Report the latest osd_map from all OSDs.
#

use strict;

my %hosts;

open my $fd, "ceph osd tree |"
    or die "can't run ceph: $!";
my $host = '';
while (<$fd>)
{
    my @f = split;
    if ($f[2] eq 'host')
    {
	$host = $f[3];
	next;
    }
    if ($f[2] =~ /^osd\./)
    {
	$hosts{$host} = [] if !defined $hosts{$host};
	push @{$hosts{$host}}, $f[2];
    }
}

my $min_osd;
my $max_osd;
my $min_map;
my $max_map;
my $min_vsz_osd;
my $max_vsz_osd;
my $min_vsz;
my $max_vsz;

for my $host (sort keys %hosts)
{
    my $req = 'ps auxww;
               for osd in ' . join(' ', @{$hosts{$host}}) . ';
               do
                 ceph daemon $osd status;
               done';
    open my $fd,
    "ssh $host '$req' 2>/dev/null |"
	or die "can't run ssh: $!";
    my %newest_maps;
    my %VSZs;
    my %RSSs;
    my %pids;
    my $id = '';
    while(<$fd>)
    {
	# "whoami": 3,
	if (/"whoami": (\d+),/)
	{
	    $id = $1;
	    next;
	}
	# "newest_map": 50,
	if (/"newest_map": (\d+),/)
	{
	    my $newest_map = $1;
	    $newest_maps{$id} = $newest_map;
	    if (!defined $min_map || $newest_map < $min_map)
	    {
		$min_map = $newest_map;
		$min_osd = "osd.$id";
	    }
	    if (!defined $max_map || $newest_map > $max_map)
	    {
		$max_map = $newest_map;
		$max_osd = "osd.$id";
	    }
	    next;
	}
	# USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
	# root      4302  0.1  3.6 648840 113512 ?       Ssl  Oct02  29:43 /usr/bin/ceph-osd --cluster=ceph -i 3 -f
	if (m|^[^\s]+\s+(\d+)\s+[\d.]+\s+[\d.]+\s+(\d+)\s+(\d+)\s+.*\s+/usr/bin/ceph-osd\s+.*\s+-i\s+(\d+)|)
	{
	    my $pid = $1;
	    my $vsz = $2;
	    my $rss = $3;
	    my $id  = $4;
	    $pids{$id} = $pid;
	    $VSZs{$id} = $vsz;
	    $RSSs{$id} = $rss;
	    if (!defined $min_vsz || $vsz < $min_vsz)
	    {
		$min_vsz = $vsz;
		$min_vsz_osd = "osd.$id";
	    }
	    if (!defined $max_vsz || $vsz > $max_vsz)
	    {
		$max_vsz = $vsz;
		$max_vsz_osd = "osd.$id";
	    }
	    next;
	}
    }
    close $fd;
    for my $osd (@{$hosts{$host}})
    {
	next if $osd !~ /^osd\.(\d+)/;
	my $id = $1;
	my $pid = defined $pids{$id} ? $pids{$id} : '-';
	my $vsz = defined $VSZs{$id} ? $VSZs{$id} : '-';
	my $rss = defined $RSSs{$id} ? $RSSs{$id} : '-';
	my $newest_map = defined $newest_maps{$id} ? $newest_maps{$id} : '-';
	print "${host} ${osd}[${pid}] VSZ=${vsz} RSS=${rss} newest_map=${newest_map}\n";
    }
    print "\n";
}

if (defined $min_map && defined $max_map)
{
    print "--\n";
    print "min_map: $min_map ($min_osd)\n";
    print "max_map: $max_map ($max_osd)\n";
    print "maxdiff: " . ($max_map - $min_map) . "\n";
}

if (defined $min_vsz && defined $max_vsz)
{
    print "--\n";
    print "min_vsz: $min_vsz ($min_vsz_osd)\n";
    print "max_vsz: $max_vsz ($max_vsz_osd)\n";
}
