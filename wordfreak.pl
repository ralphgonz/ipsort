#!/usr/bin/perl
# wordfreak
# R. Gonzalez 2016-02-04
#
#   perl wordfreak.pl < inputfile > outputfile
#
# Output list of words sorted by frequency. This list
# may exceed memory size. If so, use external sort.
# Mostly old-skool procedural plus OOP
#
#   * Read from stdin
#   * Periodically check memory usage. If small:
#   *   Sort unique words on frequency and write to stdout
#   * Else
#   *   Create N subsets in external files sorted alpha, with frequency info
#   *   Merge sort subsets alpha, combining frequency info, and write to multiple subsets each sorted on frequency
#   *   Merge sort new subsets on frequency
#   *   Write to stdout
#

use strict;
use Devel::Size;

my $FILE_PREFIX = "subset";
chomp(my $MEM_AVAIL = qx(echo `ulimit -Sv`));
my $MAX_MEM_FRACTION = 0.25;

###############################################################################
package Subset;

sub new {
	my ($class, $fileName) = @_;
	my $self = {
		'fileName' => $fileName,
		'uniqueWords' => {},
		'sortedWords' => [],
	};
    	bless $self, $class;
    	return $self;
}

sub loadNextValueFromStdin {
	my ($self) = @_;
	chomp(my $val = <STDIN>);
	return 0 if (!defined($val));
	$val =~ s/^.+?,//; # strip off user name
	my @words = split /[^\p{IsAlnum}\u2019\'\@]+/, $val; # word boundary is anything other than alphanumeric or apostrophe or @
	foreach my $word (@words) {
		next if (length($word) == 0);
		++$self->{uniqueWords}->{$word};
	}
	return 1;
}

sub loadNewValue {
	my ($self, $val, $freq) = @_;
	$self->{uniqueWords}->{$val} = $freq;
}

sub writeNextValueToStdout {
	my ($self) = @_;
	print "$self->{nextVal}->{val}\n";
}

sub writeToStdout {
	my ($self) = @_;
	foreach my $word (@{$self->{sortedWords}}) {
		print "$word\n";
	}
}

sub createSortedFile {
	my ($self, $sortOnFreq, $purge) = @_;
	
	if ($sortOnFreq) {
		# Sort words by descending frequency then alphabetical:
		$self->{sortedWords} = [sort {$self->{uniqueWords}->{$b} <=> $self->{uniqueWords}->{$a} || $a cmp $b } (keys %{$self->{uniqueWords}})];
	} else {
		# Sort words alphabetical:
		$self->{sortedWords} = [sort { $a cmp $b } (keys %{$self->{uniqueWords}})];
	}
	return if (!$purge);
	
	print STDERR "Creating subset file $self->{fileName}\n";
	open (my $fh, '>', $self->{fileName}) || die "Can't write to $self->{fileName}";
	foreach my $val (@{$self->{sortedWords}}) {
		print $fh "$val,$self->{uniqueWords}->{$val}\n";
	}

	undef $self->{uniqueWords};
	undef $self->{sortedWords};
}

sub openToRead {
	my ($self) = @_;
	open (my $fh, '<', $self->{fileName}) || die "Can't read from $self->{fileName}";
	$self->{fileHandle} = $fh;
}

sub readNext {
	my ($self) = @_;
	my $fh = $self->{fileHandle};
	chomp(my $line = <$fh>);
	if (!defined($line)) {
		undef $self->{nextVal};
	} else {
		($self->{nextVal}->{val}, $self->{nextVal}->{freq}) = split /,/, $line;
	}
}

###############################################################################
package main;
	
	my @subsets = readDataAndCreateSubsets();
	if (scalar(@subsets) == 1) {
		$subsets[0]->writeToStdout();
	} else {
		my @freqSortedSubsets = mergeSortSubsetsAndWrite(\@subsets, 1);
		mergeSortSubsetsAndWrite(\@freqSortedSubsets, 0);
	}
				
	exit(0);
	
###################
sub memFraction {
	my ($v) = @_;
	return 0 if ($MEM_AVAIL eq "unlimited");
	my $size = Devel::Size::total_size($v);
	return $size / ($MEM_AVAIL * 1024);
}

###################
sub readDataAndCreateSubsets {
	my @subsets; 
	my $subset = new Subset($FILE_PREFIX . scalar(@subsets));
	my $dataRemaining;
	my $nLinesRead = 0;
	do {
		my $memUsed;
		if (++$nLinesRead % 1000000 == 0) {
			$memUsed = memFraction($subset);
			print STDERR "Read line: $nLinesRead, Mem usage: $memUsed...\n";
		}
		
		$dataRemaining = $subset->loadNextValueFromStdin();
		if (!$dataRemaining || $memUsed > $MAX_MEM_FRACTION) {
			my $inMemory = (!$dataRemaining && scalar(@subsets) == 0);
			$subset->createSortedFile($inMemory, !$inMemory);
			push @subsets, $subset;
			$subset = new Subset($FILE_PREFIX . scalar(@subsets));
		}
	} while ($dataRemaining);
	return @subsets;
}

###################
sub mergeSortSubsetsAndWrite {
	my ($subsets, $reEncode) = @_;
	
	my @subsets2; 
	my $subset2 = new Subset($FILE_PREFIX . "-freq" . scalar(@subsets2));
	
	foreach my $subset (@{$subsets}) {
		$subset->openToRead();
		$subset->readNext();
	}
	
	my $nextSubsetToReadFrom;
	my $nLinesWritten = 0;
	do {
		my $memUsed;
		if (++$nLinesWritten % 1000000 == 0) {
			$memUsed = memFraction($subset2);
			print STDERR "Write line: $nLinesWritten, Mem usage: $memUsed...\n" ;
		}
		undef $nextSubsetToReadFrom;
		foreach my $subset (@{$subsets}) {
			next if (!defined($subset->{nextVal}));
			if (!$nextSubsetToReadFrom) {
				$nextSubsetToReadFrom = $subset;
			} elsif ($reEncode) {
				# sort alphabetically
				if ($subset->{nextVal}->{val} lt $nextSubsetToReadFrom->{nextVal}->{val}) {
					$nextSubsetToReadFrom = $subset;
				}
			} else {
				# sort on descending frequency
				if ($subset->{nextVal}->{freq} > $nextSubsetToReadFrom->{nextVal}->{freq}) {
					$nextSubsetToReadFrom = $subset;
				}
			}
		}
		if ($nextSubsetToReadFrom) {
			if ($reEncode) {
				# combine frequencies from multiple alpha-sorted files
				my $totalFreq = 0;
				my $val = $nextSubsetToReadFrom->{nextVal}->{val};
				foreach my $subsetNestedPass (@{$subsets}) {
					if ($subsetNestedPass->{nextVal}->{val} eq $val) {
						$totalFreq += $subsetNestedPass->{nextVal}->{freq};
						$subsetNestedPass->readNext();
					}
				}
				$subset2->loadNewValue($val, $totalFreq);
			} else {
				$nextSubsetToReadFrom->writeNextValueToStdout();
				$nextSubsetToReadFrom->readNext();
			}
		}
		if ($reEncode && (!$nextSubsetToReadFrom || $memUsed > $MAX_MEM_FRACTION)) {
			$subset2->createSortedFile(1, 1);
			push @subsets2, $subset2;
			$subset2 = new Subset($FILE_PREFIX . "-freq" . scalar(@subsets2));
		}
	} while ($nextSubsetToReadFrom);
	
	return @subsets2;
}

