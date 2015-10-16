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

for my $host (sort keys %hosts)
{
    my $req = 'for osd in ' . join(' ', @{$hosts{$host}}) . '; do ceph daemon $osd status; done';
    open my $fd,
    "ssh $host '$req' 2>/dev/null |"
	or die "can't run ssh: $!";
    my %newest_maps;
    my $id = '';
    while(<$fd>)
    {
	if (/"whoami": (\d+),/)
	{
	    $id = $1;
	    next;
	}
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
	}
    }
    close $fd;
    for my $osd (@{$hosts{$host}})
    {
	next if $osd !~ /^osd\.(\d+)/;
	my $id = $1;
	my $newest_map = defined $newest_maps{$id} ? $newest_maps{$id} : '-';
	print "$host $osd $newest_map\n";
    }
    print "\n";
}

if (defined $min_map && defined $max_map)
{
    print "min_map: $min_map ($min_osd)\n";
    print "max_map: $max_map ($max_osd)\n";
    print "maxdiff: " . ($max_map - $min_map) . "\n";
}
