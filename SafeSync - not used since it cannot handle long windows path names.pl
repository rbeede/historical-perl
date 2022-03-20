# Author:  Rodney Beede
#
use constant VERSION => "2010-08-28";
#
#
# Does not support symbolic links
#
# Always ignores pathnames containing the following case sensitive strings:
#	$RECYCLE.BIN
#	RECYCLER
#	System Volume Information


# This will dyanmically load the script directory as a perl library path
# This allows us to not require installing external libaries into perl
BEGIN {
	my $myScriptLoc = "";
	use File::Spec::Functions qw(rel2abs);
	use File::Basename qw(dirname);
	# Perl always makes $0 work if it is actually a file (and not perl -e code)
	$myScriptLoc = dirname(rel2abs($0));
	push(@INC, "$myScriptLoc/lib");
}


use strict;
require 5.10.0;

use subs qw(logMessage logInfo logError emailLog);
my $logData;

use File::Find;
use POSIX qw(strftime);
use File::Copy;
use File::Basename qw(dirname);
use File::Path;


my $scriptDirectory = File::Basename::dirname(File::Spec->rel2abs($0));
my $scriptFilename = File::Basename::basename(File::Spec->rel2abs($0));


my @excludes = ("\$RECYCLE.BIN", "RECYCLER", "System Volume Information", ".svn");



# ******************
# Global variables for holding arguments given to program

my $sourceDirectory;
my $destDirectory;

my $startDatestamp = time;



main();  # For scoping

sub main {
	if(@ARGV < 2) {
		print STDERR "Insufficient number of arguments\n";
		usage();
		exit(255);
	}
		
	my $parsedArgIdx = -1;
	
	$sourceDirectory = $ARGV[++$parsedArgIdx];
	$destDirectory = $ARGV[++$parsedArgIdx];
	
	if(! -d $sourceDirectory) {
		logError("Source Directory '$sourceDirectory' is not an existing directory");
		recordLog();
		exit(254);
	} elsif(! -d $destDirectory) {
		logError("Destination Directory '$destDirectory' is not an existing directory");
		recordLog();
		exit(253);
	}
	
	# Convert from \ to /
	$sourceDirectory =~ s/\\/\//g;
	$destDirectory =~ s/\\/\//g;
	
	# Make sure they end in '/'
	if($sourceDirectory !~ /\/$/) {
		$sourceDirectory .= "/";
	}
	if($destDirectory !~ /\/$/) {
		$destDirectory .= "/";
	}
	
	
	logInfo "$0 of $sourceDirectory to $destDirectory";
	

	# Listing keys
	#		{entry pathname}
	#											{"byte size"}
	#											{"modified date"}
	#
	#		entry pathname is the full pathname minus the sourceDirectory or destDirectory part
	#
	#		"byte size" == -1 signals entry is a directory
	#			When a directory ignore the "modified date" as it changes all the time
	
	my %sourceListing;
	my %destListing;
	
	
	#***********************************************
	# Get a complete sourceListing
	logInfo("Getting listing of $sourceDirectory...");
	find(sub {
		my $fullPathname = $File::Find::name;
		my $directory = $File::Find::dir;
		my $filename = $_;

		# Do we have an exclude?
		foreach my $exclude (@excludes) {
			if(index($fullPathname,$exclude) != -1) {
				return;  # Skip it
			}
		}

		my $entryPathname = substr($fullPathname, length($sourceDirectory));   # trim off front part to make relative
		
		if("" eq $entryPathname) {
			# Found ourself
			return;
		}

		$sourceListing{$entryPathname}{"modified date"} = (stat($fullPathname))[9];
		if(! -d $fullPathname) {
			$sourceListing{$entryPathname}{"byte size"} = (stat($fullPathname))[7];
		} else {
			$sourceListing{$entryPathname}{"byte size"} = -1;  # signals directory
		}
	}, $sourceDirectory);
	
	#***********************************************
	# Get a complete destListing
	logInfo("Getting listing of $destDirectory...");
	find(sub {
		my $fullPathname = $File::Find::name;
		my $directory = $File::Find::dir;
		my $filename = $_;

		# Do we have an exclude?
		foreach my $exclude (@excludes) {
			if(index($fullPathname,$exclude) != -1) {
				return;  # Skip it
			}
		}
		
		my $entryPathname = substr($fullPathname, length($destDirectory));  # trim off front part to make relative

		if("" eq $entryPathname) {
			# Found ourself
			return;
		}
		
		$destListing{$entryPathname}{"modified date"} = (stat($fullPathname))[9];
		if(! -d $fullPathname) {
			$destListing{$entryPathname}{"byte size"} = (stat($fullPathname))[7];
		} else {
			$destListing{$entryPathname}{"byte size"} = -1;  # signals directory
		}
	}, $destDirectory);
	
	
	#***********************************************
	# Some variables for holding reporting information
	my @extraFiles;  # in destination but not source
	# same key format as sourceListing
	# files already in destination that look different from source files
	my @existingDifferentFiles;
	
	
	#***********************************************
	# Copy any files not in the destination already
	logInfo("Copying files not in destination (if any)...");
	foreach my $srcEntry (keys %sourceListing) {
		if(!defined($destListing{$srcEntry})) {
			# Need to copy the file
			logInfo "\t" . $srcEntry;

			my $sourcePathname = $sourceDirectory . $srcEntry;
			my $destinationPathname = $destDirectory . $srcEntry;
			
			if(-1 == $sourceListing{$srcEntry}{"byte size"}) {  # just a directory?
				# just make the directory
				mkpath $destinationPathname;
			} else {  # do a file copy
				# create parent directories if needed
				my $parentDir = dirname($destinationPathname);
				if(! -d $parentDir) {
					mkpath $parentDir;
				}
				
				if(!copy($sourcePathname, $destinationPathname)) {
					logError "Failed to copy $sourcePathname to $destinationPathname because $!";
				}

				# Attempt to preserve the last modified time for the destination file
				utime $sourceListing{$srcEntry}{"modified date"}, $sourceListing{$srcEntry}{"modified date"}, $destinationPathname;
			}
		} else {  # check to make sure they are the same
			if(	
					(-1 != $sourceListing{$srcEntry}{"byte size"}) &&
					(
					($sourceListing{$srcEntry}{"byte size"} != $destListing{$srcEntry}{"byte size"}) ||
					($sourceListing{$srcEntry}{"modified date"} != $destListing{$srcEntry}{"modified date"})
					)
				) {
					push @existingDifferentFiles, $srcEntry;  # so we can log it later
			}
		}
	}
	logInfo("Done copying files not in destination");
	
	
	#***********************************************
	# Did we have any existing different files?
	if(@existingDifferentFiles > 0) {
		logError "EXISTING FILES IN DESTINATION HAVE DIFFERENT CHARACTERISTICS AND WERE NOT COPIED!!!";
		logInfo "List of mismatched files follows:";
		
		my $reportList = "\n";
		
		$reportList .= "Filename\tSource Byte Size\tSource Modified Epoch\tDestination Byte Size\tDestination Modified Epoch\n";
		
		foreach my $entry (sort @existingDifferentFiles) {
			$reportList .= "$entry";
			$reportList .= "\t";
			$reportList .= $sourceListing{$entry}{"byte size"};
			$reportList .= "\t";
			$reportList .= $sourceListing{$entry}{"modified date"};
			$reportList .= "\t";
			$reportList .= $destListing{$entry}{"byte size"};
			$reportList .= "\t";
			$reportList .= $destListing{$entry}{"modified date"};
			$reportList .= "\n";
		}
		
		logInfo $reportList;
		logInfo "End of mismatched files report";
	}
	
	
	#***********************************************
	# Look for extra files in the destination
	foreach my $destEntry (keys %destListing) {
		if(!defined($sourceListing{$destEntry})) {
			push @extraFiles, $destEntry;
		}
	}
	
	if(@extraFiles > 0) {
		logError "EXTRA FILES IN DESTINATION";
		logInfo "List of extra files follows:";
		
		logInfo "\n" . join("\n", sort(@extraFiles));
		
		logInfo "End of extra files report";
	}
	
	
	logInfo "Completed $0";
	
	recordLog();
}


sub usage {
	print <<EOM;
perl $scriptFilename <source directory> <destination directory>

	source directory	Source to sync from
	destination directory	Destination to write to
	
	Any extra files that exist in destination but not in source will be left alone and reported in the log.
	
	Any modified files that already exist in destination will NOT be overwritten.  They will be reported in the log.
	
EOM
}


sub logMessage {
	my $severity = shift;
	my $msg = shift;
	

	my $now = formatDate(time);
	
	$logData .= "$now  $severity  $msg\n";
}

sub logInfo {
	my $msg = shift;
	
	logMessage("INFO", $msg);
}

sub logError {
	my $msg = shift;
	
	logMessage("ERROR", $msg);
}


sub recordLog {
	my $logFilename = "$scriptFilename" . "_log_" . formatDate($startDatestamp) . ".txt";
	
	if($logData =~ /ERROR/) {
		$logFilename = "ERROR_$logFilename";
	}
	
	open(FH, ">", $logFilename) || die("Unable to write log!\n\t$!\n");
	
	print FH "$scriptFilename of $sourceDirectory to $destDirectory" . "\n";

	print FH $logData;
	
	close(FH);
}


# Returned date format is in local time zone
sub formatDate {
	my $epochSeconds = shift;
	
	# POSIX gives us yyyy-mm-dd__HH-MM-SS__-zzzz (adds in leading 0's for us)
	return strftime("%Y-%m-%d__%H-%M-%S__", localtime($epochSeconds)) . timezoneOffsetFormatted();
}


# Gets the timezone offset based on the current local timezone
# Could have used DateTime::Format but that requires installing
#	it and lots of dependencies
# Returned value is in seconds
# Based on http://stackoverflow.com/questions/2632104/how-do-i-elegantly-print-the-z-timezone-format-in-perl-on-windows
sub tzoffset {
    my $t = time();
    my $utc = POSIX::mktime(gmtime($t));
    my @tmlocal = localtime($t);
    $tmlocal[8] = 0; # force dst off, timezone specific
    my $local = POSIX::mktime(@tmlocal);

    return ($local - $utc);
}

# Returns timezone difference from UTC/GMT in hh:mm or -hh:mm format
# Based on http://stackoverflow.com/questions/2632104/how-do-i-elegantly-print-the-z-timezone-format-in-perl-on-windows
sub timezoneOffsetFormatted {
    my ($tzoffset) = tzoffset();
    my $z = '';
    if ($tzoffset < 0) { 
        $z .= '-';
        $tzoffset *= -1;
    } 
    my $hours = POSIX::floor($tzoffset / 60 / 60);
    my $minutes = $tzoffset - $hours * 60 * 60;
    $z .= sprintf('%02d%02d', $hours, $minutes);
    return $z;
}