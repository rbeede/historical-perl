#!/usr/bin/perl

use constant VERSION => "2013-01-06";

# Rodney Beede

# Checks to see if the given file has been modified in the last X time unit


use strict;
require 5.012_001;

use File::Spec;


# for scoping
main();


sub main {
	if(2 != @ARGV) {
		print "Usage:\tperl $0 <full path to file> <hours>\n";
		print "\n";
		exit(255);
	}
	
	my $fileResolved = File::Spec->rel2abs($ARGV[0]);

	my $fileLastModEpoch = (stat($fileResolved))[9];
	
	if(!defined($fileLastModEpoch) || $fileLastModEpoch < 0) {
		print STDERR "Unable to stat file $fileResolved for some reason, does it exist?\n";
		print STDERR "\n";
		exit(254);
	} else {
		print "Looking at file $fileResolved\n";
		print "File's last modified is " . localtime($fileLastModEpoch) . "\n";
	}
	
	
	# Epoch seconds calculation so DST does not affect
	my $timeDifference = time() - $fileLastModEpoch;
	
	print "It is " . ($timeDifference / 60 / 60) . " hours old\n";
	
	
	# Sanity check
	if($timeDifference < 0) {
		# Negative indicates incorrect clock somewhere since file should not be in the future
		print STDERR "FILE LAST MOD DATE OR SYSTEM TIME IS INCORRECT.  FILE APPEARS TO BE IN THE FUTURE!\n";
		exit(253);
	}
	
	my $hours = $ARGV[1];
	
	if($timeDifference > ($hours * 60 * 60)) {  # hours to seconds
		print STDERR "FILE LAST MOD DATE IS MORE THAN $hours hours OLD!!!\n";
		exit(1);
	} else {
		print "File passed check of within $hours hours.";
		exit(0);
	}
}