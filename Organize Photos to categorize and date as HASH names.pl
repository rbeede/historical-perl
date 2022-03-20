#
# 2012-04-22
#


require 5.12.0;

use strict;
use warnings;


use File::Find;
use Digest::MD5;
use File::Spec;
use File::stat;
use File::basename;


##################
# Global variables

##################
# Prototypes



#######
main();  # For better scoping


sub main {
	if(@ARGV < 1) {
		print "$0 \"<source directory full pathname>\"\n";
		print "Renames FILES to hash value\n";
		exit(1);
	}
	
	
	my $sourceDirectory = File::Spec->rel2abs($ARGV[0]);
	
	
	if(! -d $sourceDirectory) {
		die("$sourceDirectory is not a directory!\n");
	} else {
		print "Using source directory of $sourceDirectory\n";
	}
	
	
	my $destinationDirectory = $sourceDirectory . "__PREPPED";

	
	# Go through all the files in sourceDirectory
	find(
			sub {
				my $currFullPathname = $File::Find::name;
			
				if( -d $currFullPathname ) {
					return;
				} else {
					printf $currFullPathname . "\n";
				}
				
				my $fileStat = stat($currFullPathname) or die "Error:  $!\n";
				
				my $newFilename = $fileStat->mtime;
				$newFilename .= "_";
				
				my $fileDigest = digestFile($currFullPathname);
				$newFilename .= $fileDigest;
				
				$newFilename .= substr($currFullPathname, -4);  # grabs .ext part
				
				$newFilename = lc($newFilename);  # make this part standard (directory parts may be case sensitive so leave alone)
				
				# Any files that were in subfoldrs of sourceDirectory are just dumped into 1 root directory for the destination with the new filename
				# the subfolders were mostly just dates of the scan, but we already have that info
				my $newFullPathname = $destinationDirectory . "/" . $newFilename;
				
				
				if(-e $newFullPathname) {
					# Either move failed last time or duplicate file
					print "\tDUPLICATE RENAMED AND REMOVED\n";
				}
				
				
				print "\t==>\t" . $newFullPathname . "\n";
				
				
				# Not platform independent always and may not handle moves across partitions, but fast and good enough
				my $result = rename($currFullPathname, $newFullPathname);
				
				if(!$result) {
					print STDERR ("RENAME FAILED!\n");
					die("no specific error message available, trying to move across partitions not supported?\n");
				}
			}
		,
		$sourceDirectory
	);
	

}


sub digestFile {
	my $fullPath = shift;
	
	
	my $digest;
	
	if(!open(FH, "<", $fullPath)) {
		print STDERR $fullPath;
		print STDERR "\t";
		print STDERR "$!";
		print STDERR "\n";
		
		exit(255);
		
		return;
	}
	binmode(FH);
	
	$digest = Digest::MD5->new->addfile(*FH)->hexdigest;
	
	close(FH);
	
	
	return $digest;
}

	
	