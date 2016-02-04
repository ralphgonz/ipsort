#!/usr/bin/perl
# ipsort
# R. Gonzalez 2016-01-29
#
#   perl ipsort.pl < inputfile > outputfile
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
# use Sys::MemInfo;
# use Devel::Size;
# use Net::IP; # Way too slow!
# use Math::BigInt; # Way too slow!

my $FILE_PREFIX = "subset";
my $MAX_VAL = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff";
# my $MAX_VAL = ipv6ToNumericString("ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff");
my $BIGINT_SIZE = 88; # Devel::Size::total_size($MAX_VAL);
chomp(my $MEM_AVAIL = qx(echo `ulimit -Sv`)); # Sys::MemInfo::totalswap();
my $MAX_ELEMENTS = ($MEM_AVAIL eq "unlimited" ? undef : int($MEM_AVAIL * 1024 / $BIGINT_SIZE / 3));
print STDERR "Max subset size: $MAX_ELEMENTS\n";

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
	chomp(my $val = <STDIN>);
	return undef if (!defined($val));
	return $self->loadNextValueFromStdin() if (!$val);
 	push @{$self->{list}}, $val;
	return $val;
# 	(my $ip = new Net::IP($val)) || return $self->loadNextValueFromStdin();
# 	my $bigIntVal = $ip->intip();
# 	push @{$self->{list}}, $bigIntVal;
# 	return $bigIntVal;
}

sub writeNextValueToStdout {
	my ($self) = @_;
	print "$self->{nextVal}\n";
#  	my $ip = Net::IP::ip_bintoip(Net::IP::ip_inttobin($self->{nextVal}, 6), 6);
# 	print "$ip\n";
}

sub createSortedFile {
	my ($self) = @_;
	
	my @sortedList = sort @{$self->{list}};
# 	my @sortedList = sort { $a->bcmp($b) } @{$self->{list}};
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
		print STDERR "Read: $nLinesRead...\n" if (++$nLinesRead % 1000000 == 0);
		$dataRemaining = $subset->loadNextValueFromStdin();
		if (!$dataRemaining || ($MAX_ELEMENTS && scalar(@{$subset->{list}}) >= $MAX_ELEMENTS)) {
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
		print STDERR "Write: $nLinesWritten...\n" if (++$nLinesWritten % 1000000 == 0);
		undef $nextSubsetToReadFrom;
		foreach my $subset (@subsets) {
			next if (!defined($subset->{nextVal}));
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

