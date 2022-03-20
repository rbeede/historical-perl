# 2012-07-01
#
# Grabs last modified date of all files in current directory and outputs a Windows batch script
#	that can rename them with the YYYY-MM-DD_HH-mm-SS_UTC_ prefix added
# So redirect the output (STDOUT) to a .cmd or .bat file and execute it
#
# Paths are left relative.  Time is marked in UTC time zone.


use strict;
use warnings;

use POSIX qw(strftime);
use Cwd;

print "\@REM	Looking at " . getcwd() . "\n";
print "\n";

opendir(DIR_FH, getcwd()) or die("$!\n");


while(my $filename = readdir(DIR_FH)) {
	if($filename eq "." or $filename eq "..") {
		next;
	}
	
	
	# mtime    last modify time in seconds since the epoch
	#	note that the epoch isn't necessarily Jan 1, 1970 GMT
	#	It shouldn't matter since only APIs are used in date conversions
	my $lastModifiedEpoch = (stat($filename))[9];

	# POSIX gives us yyyy-mm-dd__HH-MM-SS__ (adds in leading 0's for us)
	my $lastModifiedForPrinting = strftime("%Y-%m-%d_%H-%M-%S_UTC__", gmtime($lastModifiedEpoch));
	
	print 'RENAME "';
	print $filename;
	print '" "';
	print $lastModifiedForPrinting;
	print $filename;
	print '"';
	print "\n\n";
}

closedir(DIR_FH);