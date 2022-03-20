#
# Author:  Rodney Beede
#
use constant VERSION => "2013-08-08";
#
# Tested with Perl 5.14
#
#


use strict;
use warnings "all";

# mx=9 means max compression
# ms=on means solid mode
# mmt=2 means multithread mode with 2 threads (best compression ratio is 2)
# mtc=on means store file creation timestamps
# m0=LZMA2 means use LZMA2
# t7z means use 7-zip format
use constant COMPRESS_COMMAND => qq{"c:/Program Files/7-Zip/7z.exe" a "INSERT_SOURCE_FILENAME.7z" "INSERT_SOURCE_FILENAME" -mx=9 -ms=on -mmt=2 -mtc=on -m0=LZMA2 -t7z};

use File::Spec;
use File::Basename;


my $scriptFilename = File::Basename::basename(File::Spec->rel2abs($0));


main();  # scoping


sub main {
	if(@ARGV != 1) {
		usage();
		exit(0);
	}
	
	my $sourceDirectory = $ARGV[0];
	
	if(! -d $sourceDirectory) {
		print STDERR "$sourceDirectory is not a directory!\n";
		exit(255);
	} else {
		print "Using source directory of $sourceDirectory\n";
		print "\n";
	}
	
	
	opendir(SRC_DH, $sourceDirectory) or die("Unable to open $sourceDirectory\n\t$!\n");
	
	while($_ = readdir(SRC_DH)) {
		my $currSourceFullPathname = $sourceDirectory . "/" . $_;
		
		if(! -f $currSourceFullPathname) {
			next;  # skip non-files
		} elsif($currSourceFullPathname =~ m/\.7z$/i) {
			print "$currSourceFullPathname is already compressed, skipping\n";
			next;
		}
		
		print "Processing $currSourceFullPathname...\n";
		
	
		my $currCmd = COMPRESS_COMMAND;
		$currCmd =~ s/INSERT_SOURCE_FILENAME/$currSourceFullPathname/g;
		
		print "\tRunning command $currCmd";
		
		if(0 != (system($currCmd) >> 8)) {
			die("Command failed with error exit code\n");
		}
	}
	
	closedir(SRC_DH);
}


sub usage {
	print "perl $scriptFilename /path/to/src/dir/\n";
	print "\n";
}
