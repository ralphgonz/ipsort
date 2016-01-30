#!/usr/bin/perl
# ipsort
# R. Gonzalez 2016-01-29
#
# External sort leveraging built-in sort function
# Mostly old-skool procedural plus OOP
#
#   * Read from stdin
#   * Create N sorted subsets in external files
#   * Merge subsets
#   * Write to stdout
#

use strict;
use Getopt::Long;
use Math::BigInt;
use Net::IP;
use Sys::MemInfo;
use Devel::Size;

my $FILE_PREFIX = "subset";
my $MAX_VAL = (new Net::IP("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"))->intip();
my $BIGINT_SIZE = Devel::Size::total_size($MAX_VAL);
my $MEM_AVAIL = Sys::MemInfo::freemem();
my $MAX_ELEMENTS = $MEM_AVAIL / $BIGINT_SIZE / 3;

###############################################################################
package Subset;

sub new {
	my ($class, $fileName) = @_;
	my $self = {
		'fileName' => $fileName,
		'list' => [],
	};
    	bless $self, $class;
    	return $self;
}

sub loadNextValueFromStdin {
	my ($self) = @_;
	(my $val = <STDIN>) || return undef;
	chomp $val;
	(my $ip = new Net::IP($val)) || return $self->loadNextValueFromStdin();
	my $bigIntVal = $ip->intip();
	push @{$self->{list}}, $bigIntVal;
	return $bigIntVal;
}

sub createSortedFile {
	my ($self) = @_;
	
	my @sortedList = sort { $a->bcmp($b) } @{$self->{list}};
	open (my $fh, '>', $self->{fileName}) || die "Can't write to $self->{fileName}";
	foreach my $val (@sortedList) {
		print $fh "$val\n";
	}

	undef $self->{list};
}

sub openToRead {
	my ($self) = @_;
	open (my $fh, '<', $self->{fileName}) || die "Can't read from $self->{fileName}";
	$self->{fileHandle} = $fh;
}

sub readNext {
	my ($self) = @_;
	my $fh = $self->{fileHandle};
	chomp($self->{nextVal} = <$fh>);
}

sub writeNextValueToStdout {
	my ($self) = @_;
	my $ip = $self->{nextVal}; #Net::IP::ip_bintoip(Net::IP::ip_inttobin($self->{nextVal}, 6), 6);
	print "$ip\n";
}

###############################################################################
package main;
	
	my @subsets = readDataAndCreateSubsets();
	mergeSortSubsetsAndWrite(@subsets);
				
	exit(0);
	
###################
sub readDataAndCreateSubsets {
	my @subsets; 
	my $subset = new Subset($FILE_PREFIX . scalar(@subsets));
	my $dataRemaining;
	my $nLinesRead = 0;
	do {
		print STDERR "Read: $nLinesRead...\n" if ($nLinesRead++ % 1000 == 0);
		$dataRemaining = $subset->loadNextValueFromStdin();
		if (!$dataRemaining || scalar(@{$subset->{list}}) >= $MAX_ELEMENTS) {
			print STDERR "Creating subset file $subset->{fileName}\n";
			$subset->createSortedFile();
			push @subsets, $subset;
			$subset = new Subset($FILE_PREFIX . scalar(@subsets));
		}
	} while ($dataRemaining);
	return @subsets;
}

###################
sub mergeSortSubsetsAndWrite {
	my @subsets = @_;
	
	foreach my $subset (@subsets) {
		$subset->openToRead();
		$subset->readNext();
	}
	
	my $nextSubsetToReadFrom;
	my $nLinesWritten = 0;
	do {
		print STDERR "Write: $nLinesWritten...\n" if ($nLinesWritten++ % 1000000 == 0);
		undef $nextSubsetToReadFrom;
		foreach my $subset (@subsets) {
			next if (!$subset->{nextVal});
			if (!$nextSubsetToReadFrom || $subset->{nextVal} < $nextSubsetToReadFrom->{nextVal}) {
				$nextSubsetToReadFrom = $subset;
			}
		}
		if ($nextSubsetToReadFrom) {
			$nextSubsetToReadFrom->writeNextValueToStdout();
			$nextSubsetToReadFrom->readNext();
		}
	} while ($nextSubsetToReadFrom);
}

