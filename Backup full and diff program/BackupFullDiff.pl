# Author:  Rodney Beede
#
use constant VERSION => "2010-03-23";
#
# Ignores some folders always (see help)


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

use warnings;
use File::Path;
use File::Find;
use Cwd;
use Time::Local;
use File::Spec::Functions qw(rel2abs);
use File::Basename;
use POSIX qw(strftime);
use MIME::Lite;
use subs qw(logMessage logInfo logError emailLog);


use constant EMAIL_TO => "rodney.beede\@.com";

use constant EMAIL_FROM => "Backups.Daily\@.com";

use constant EMAIL_SMTP => "";


use constant COMPRESS_PROG => "7z";	# from path

use constant COMPRESS_OPTS => 
				"-t7z ".				# 7-zip type
				"-mx=9 ".				# Max compress
				"-ms=off ".			# Solid archive off
				"-mmt=on ".			# Multi-threading
				# win only	"-ssw ".				# Compress files open for writing
				"-xr!*.metadata* ".	# Exclude .metadata
				"-xr!*.svn* ".	# Excluded .svn
				"-xr!*target/*classes* ".	#Exclude target/*classes*
				# win only	"-scsWIN ". # File list is in WIN format
				
				""	# Empty string to close the end
				;
															
# Array of regex of path names to exclude (you should include these in COMPRESS_OPTS too
my @EXCLUDES = ("\\.metadata", "\\.svn", "target.*classes");


# Dynamically determine where this script is located
#		Same as BEGIN block above, but BEGIN has different scope
my $myScriptLoc = "";
$myScriptLoc = dirname(rel2abs($0));


# Global storage of all logging messages so we can e-mail them later
my $logData = "";



######################################################################
### BEGIN MAIN PROGRAM

#-------------------------------------------------
# Read args
if($#ARGV == -1) {
	help();
	exit(0);
}


if($#ARGV < 2) {
	print STDERR "Insufficent arguments\n\n";
	help();
	logError("Insufficent arguments");
	emailLog();
	exit(255);
} elsif( $#ARGV > 2) {
	print STDERR qw/Too many arguments.  Perhaps you need to enclose a path with "".\n\n/;
	help();
	logError(qw/Too many arguments.  Perhaps you need to enclose a path with ""./);
	emailLog();
	exit(255);
}


my $fldToBackup = $ARGV[0];
my $backupType = $ARGV[1];  # FULL or DIFF (case sensitive)
my $archiveFld = $ARGV[2];


# Convert any path seperator '\' to '/' for convience later on
$fldToBackup =~ s/\\/\//g;
$archiveFld =~ s/\\/\//g;


chomp($fldToBackup);
$fldToBackup =~ s/\/$//;  # Remove trailing / if any

chomp($archiveFld);
$archiveFld =~ s/\/$//;  # Remove trailing / if any


# We want to chdir to one level below where we are backing up
#		This allows the names in the archive to be cleaner
#		Note for Windows it isn't required to set the current drive
chdir "$fldToBackup";
chdir "..";


if($backupType ne "FULL" and $backupType ne "DIFF") {
	print STDERR "Invalid backup type '$backupType'\n\n";
	help();
	logError("Invalid backup type '$backupType'");
	emailLog();
	exit(255);
}

if(! -e $fldToBackup ) {
	print STDERR "Folder to backup '$fldToBackup' does not exist.\n\n";
	help();
	logError("Folder to backup '$fldToBackup' does not exist");
	emailLog();
	exit(255);
}



#-------------------------------------------------
# Generate date stamp info
my $dateStamp = formatDate(time);
logInfo "Using datestamp $dateStamp";


#-------------------------------------------------
# Create $archiveFld if necessary
if(! -e $archiveFld) {
	logInfo "Creating archive folder '$archiveFld'";
	
	mkpath($archiveFld);  # Creates all needed subdirectories
	
	if(! -e $archiveFld) {
		logError("Unable to create '$archiveFld'");
		logError("$@");
		emailLog();
		exit(255);
	}
}


#-------------------------------------------------
# Fire off backup based on type
if($backupType eq "FULL") {
	doFullBackup($fldToBackup, $archiveFld, $dateStamp);
} elsif($backupType eq "DIFF") {
	doDiffBackup($fldToBackup, $archiveFld, $dateStamp);
} else {
	logError("Unknown backup type '$backupType'.  Please fix code.");
	emailLog();
	exit(255);
}


logInfo "$0 is ending at time " . formatDate(time);


#-------------------------------------------------
# Send the e-mail of the result
emailLog();



######################################################################
### BEGIN SUBS


sub help {
print <<EOM;

Usage:  $0 <folder to backup> <FULL|DIFF> <archive folder>

  folder to backup -- Folder to backup.  Use / for path seperators.
	
  FULL|DIFF -- Perform full or diff backup.  If diff then full backup is
	             used based on "foldername.full.yyyy-mm-dd_hh-mm-ss" in
	             "archive folder"
	             
  archive folder -- Location to store backup archive in
  
  Note:  The following folders will be ignored:
EOM

	foreach my $exclude (@EXCLUDES) {
		print "\t" . $exclude . "\n";
	}

	print "\n";
}


sub formatDate {
	my $epochSeconds = shift;
	
	# POSIX gives us yyyy-mm-dd__HH-MM-SS (adds in leading 0's for us)
	return strftime("%Y-%m-%d__%H-%M-%S", localtime($epochSeconds));
}



sub doFullBackup {
	my ($fldToBackup, $archiveFld, $dateStamp) = @_;
	
	my $tailEndFolder = basename($fldToBackup);  # ex:  "subFld" in c:\some\path\subFld
	
	
	logInfo "Doing full backup of '$fldToBackup' to '$archiveFld'";

	
	my $backupFullPathname = $archiveFld . "/${tailEndFolder}--${dateStamp}.FULL.7z";
	
	if(-e $backupFullPathname) {
		logError("Tried to use archive filename '$backupFullPathname' but it already exists.");
		emailLog();
		exit(255);
	}

	# Prepare command
	my $cmd = qq{"} . COMPRESS_PROG . qq{"} . qq{ a } . COMPRESS_OPTS . qq{ "$backupFullPathname" "$fldToBackup"};

	logInfo "\tCurrent directory is " . getcwd;  # Should already be set to parent of $fldToBackup
	
	logInfo "\tRunning command $cmd";

	my @cmdOutput = runArchiveCmd($cmd, 1, 1);  # Capture STDERR,  Show progress
	
	logInfo "";
	logInfo "Backup archive file is '$backupFullPathname'";
	logInfo "\tand has size " . ((stat($backupFullPathname))[7] / 1048576) . " (MiB)";
	logInfo "";
	
}



sub doDiffBackup {
	my ($fldToBackup, $archiveFld, $dateStamp) = @_;
	
	my $tailEndFolder = basename($fldToBackup);  # ex:  "subFld" in c:\some\path\subFld
	
	
	logInfo "Doing differential backup of '$fldToBackup' to '$archiveFld'";
	
	
	#====================================
	# INFO ABOUT FOLDER TO BACKUP (all files/folders in the folder to backup)
	#		key = pathname, value = mod-date in epoch
	my %fldToBackupInfo = %{getFolderInfo($fldToBackup)};
	
	logInfo "\tFinished gathering info about folder $tailEndFolder";
	

	# Determine last full backup
	my $lastFullBackup;
	find(sub {  # Find all FULL backups
		my $currFile = $File::Find::name;  # Full path and filename
		
		if($currFile =~ /${tailEndFolder}.*FULL\.7z$/) {
			# See if $currFile is "greater than" [aka older] than our
			#		currently assumed lastFullBackup
			# So we compare by filename to determine the backup date
			#		since the last modified date could have been touched
			#		by some other process and not reflect the actual
			#		backup date
			
			if(!defined($lastFullBackup) || ($lastFullBackup eq "")) {
				$lastFullBackup = $currFile;  # first found
			} elsif($currFile gt $lastFullBackup) {
				$lastFullBackup = $currFile;
			}
		}
	}, $archiveFld);
	
	
	
	if(!defined($lastFullBackup) || $lastFullBackup eq "") {
		logError("Unable to find last full backup for '$fldToBackup'");
		emailLog();
		exit(255);
	} else {
		logInfo "Using last full backup '$lastFullBackup'";
	}


	#====================================
	# INFO FROM LAST FULL BACKUP
  my %fullBackupInfo = %{getFullBackupInfo($lastFullBackup)};  # key = pathname, value = mod-date in epoch
  


	#====================================
	# Strip out any information about any unwanted folders
	foreach my $currKey (keys %fldToBackupInfo) {
		foreach my $exclude (@EXCLUDES) {
			if($currKey =~ /$exclude/) {
				delete $fldToBackupInfo{$currKey};
				next;
			}
		}
	}
	foreach my $currKey (keys %fullBackupInfo) {
		foreach my $exclude (@EXCLUDES) {
			if($currKey =~ /$exclude/) {
				delete $fullBackupInfo{$currKey};
				next;
			}
		}
	}



	#====================================
	# Prepare some listings of what and what not to backup
	my @filesToBackup;
	my @filesDeleted;  # Files that exist in last full but not in current folder and thus are marked as "deleted"
	
	#====================================
	#	1:  get new files that should be backed up
	logInfo "\tLooking for brand new files...";
	foreach my $currFldToBackupFile (keys %fldToBackupInfo) {
		if( !defined($fullBackupInfo{"$currFldToBackupFile"}) ) {
			logInfo "\t\tNew file '$currFldToBackupFile' will be backed up";
			push @filesToBackup, $currFldToBackupFile;
		}
	}
	logInfo "\tDone looking for brand new files";



	#====================================
	#	2:  Look for files with differences
	logInfo "\tLooking for modified files...";
	foreach my $currLastFullFile (keys %fullBackupInfo) {
		if( !defined($fldToBackupInfo{$currLastFullFile}) ){
			logInfo "\t\tFile from last backup no longer exists.  Marking deleted";
			logInfo "\t\t\t'$currLastFullFile'";
			push @filesDeleted, $currLastFullFile;
		} else {
			# Look at the last modified dates of the already existing files
			#		For folders themselves we don't do this since the modified date
			#		on a folder changes all the time (anything modified inside modifies the folder)
			#		Also just because a folder's modified date has changed doesn't mean that files
			#		inside of it necessarily have
			
			if(-d qq[$fldToBackup/../$currLastFullFile]) {
				# A folder just needs to exist, mod date doesn't matter
				next;
			}
			
			
			# Compare the last modified dates
			if( $fldToBackupInfo{"$currLastFullFile"} != $fullBackupInfo{"$currLastFullFile"} ) {
				logInfo "\t\tFile has changed since last full backup.";
				logInfo "\t\t\t'$currLastFullFile'";
				logInfo "\t\t\tCURR FILE MOD:  " . formatDate($fldToBackupInfo{"$currLastFullFile"}) . " (" . $fldToBackupInfo{"$currLastFullFile"} . ")";
				logInfo "\t\t\tFULL FILE MOD:  " . formatDate($fullBackupInfo{"$currLastFullFile"}) . " (" . $fullBackupInfo{"$currLastFullFile"} . ")";
				
				push @filesToBackup, $currLastFullFile;
			}
		}
		
	}
	logInfo "\tDone looking at modified files";
	

	
	#====================================
	# Write a filelist of files removed since last full backup
	#		Placed in folder to backup so it appears in the root of the backup archive
	if(!open(DELFILELIST, ">$fldToBackup/TrimDeleted.cmd")) {
		logError("Unable to write TrimDeleted.cmd");
		logError("$!");
		return;
	}
	foreach my $deletedFile (@filesDeleted) {
		my $dosFormat = $deletedFile;
		$dosFormat =~ s/\//\\/g;  # All / to \
		
		print DELFILELIST qq{del "..\\$dosFormat"\n};  # If a directory does nothing
		print DELFILELIST qq{rmdir /s /q "..\\$dosFormat"\n};  # If not a dir this gives error but can be ignored
		print DELFILELIST "\n";
	}
	close(DELFILELIST);
	
	push @filesToBackup, "$tailEndFolder/TrimDeleted.cmd";
	
	
	# Write a filelist of files to backup
	push @filesToBackup, 	"$tailEndFolder/backup_filelist";
	if(!open(BACKUPFILELIST, ">$fldToBackup/backup_filelist")) {  # Will be placed in folder to backup
		logError("Unable to write backup_filelist");  
		logError("$!");
		return;
	}
		
	foreach my $fileToBackup (@filesToBackup) {
		print BACKUPFILELIST $fileToBackup . "\n";
	}
	close(BACKUPFILELIST);
	
	
	
	#====================================
	# BACKUP
	my $backupPathname = $archiveFld . "/${tailEndFolder}--${dateStamp}.DIFF.7z";

	if(-e $backupPathname) {
		logError("Tried to use archive filename '$backupPathname' but it already exists.");
		emailLog();
		exit(255);
	}

	logInfo "Compressing modified files to $backupPathname";

	
	# Current directory should already be set to parent of $tailEndFolder
	#		This places $tailEndFolder as a directory in the archive
	logInfo "\tCurrent directory is " . getcwd;  #Should already be parent of $fldToBackup
	
	
	my $cmd = qq{"} . COMPRESS_PROG . qq{"} . qq{ a } . COMPRESS_OPTS . qq{ "$backupPathname" "\@$tailEndFolder/backup_filelist"};

	logInfo "\tRunning command $cmd";
	my @cmdOutput = runArchiveCmd($cmd, 1, 1);  # Capture STDERR,  Do show progress

	unlink "$tailEndFolder/backup_filelist";
	unlink "$tailEndFolder/TrimDeleted.cmd";
	
	logInfo "";
	logInfo "Backup archive file is '$backupPathname'";
	logInfo "\tand has size " . ((stat($backupPathname))[7] / 1048576) . " (Megabytes)";
	logInfo "";
}




#
# Note that global EXCLUDES will be used to exclude path names
#
#	Parameters:
#		$fld			Required.  Full pathname of folder to recurse for info
#
# Return:			Reference to hash with recursive folder listing
#								key is "basename($fld)/subitem"
#								value is modification date of file or -1 for directories
#
# Example:
#
#							getFolderInfo("D:/Work")
#
#							This would return a reference to a hash with (not necessarily ordered):
#								{Work/FldA} = -1
#								{Work/FldB} = -1
#								{Work/FldA/File1} = 1219231740
#								{Work/FldA/File2} = 1119231741
#								{Work} = -1
sub getFolderInfo {
	my $fld = shift;
	

	my $prefix = basename($fld);  # Name of $fld without ancestor parts
	

	my %fldListing;
	find(
		{ no_chdir => 1, wanted =>
			sub {
				my $fullPathname = $File::Find::name;

				foreach my $exclude (@EXCLUDES) {
					my $regEx = qr/$exclude/;
					
					if($fullPathname =~ m{$regEx}) {
						return;
					}
				}
				
				
				# Strip off beginning $fld part
				my $listingName = substr($fullPathname, length($fld));
				
				# Add on the last part from $fld
				$listingName = $prefix . $listingName;

				
				if(-d $fullPathname) {
					$fldListing{$listingName} = -1;  # Mod date is ignored for dirs
				} else {
					$fldListing{$listingName} = (stat($fullPathname))[9];  # Mod date
				}
			}
		}, # end of options
		$fld  # 2nd arg, folder to search
	);
	

	return \%fldListing;
}



##########
#
# param:  $cmd - Command to execute (with arguments space separated and quoted)
#						Warning that passed $cmd is not untainted
#
# param:  $quitOnError - Terminates 
#
# param:  $captureSTDERR - Redirects STDERR to STDOUT.  Otherwise STDERR is ignored.
#
# param:  $displayProgress - Output STDOUT from command to STDOUT (show output)
#
#
# return:	Error occurs
#						Dumps to STDOUT the results from the command's STDOUT
#						If quitOnError then calls  exit(EXIT_CODE)
#					No error occurs
#						Returns array with each entry representing a line from STDOUT
#						Will not contain STDERR unless you set captureSTDERR
##########
sub runArchiveCmd() {
	my $cmd = shift;
	my $captureSTDERR = shift || 0;
	my $displayProgress = shift || 0;
	
	if($captureSTDERR) {
		$cmd .= " 2>&1";
	}
	
	my $cmdFH;
	if(!open($cmdFH, "$cmd|")) {
		logError("Unable to execute command");
		logInfo("Command was $cmd");
		return;
	}


	my @cmdOutput;
	
	while(<$cmdFH>) {  # Store the command output from STDOUT (STDERR has to be redirected)
		push @cmdOutput, $_;

		if($displayProgress != 0) {
			chomp($_);
			logInfo $_;
		}
	}
	
	close($cmdFH);
		
	
	# Perl has POSIX limited exit codes that max at 16 bits
	#		Shift 8 bits to get the program's return code
	my $exitCode = $? >> 8;
	
	if($exitCode != 0) {
		logError "Error during execution of $cmd.  Exit code $exitCode was returned.";
		logInfo "Output of command was:";
		foreach my $stdoutLine (@cmdOutput) {
			logInfo "\t$stdoutLine";
		}
		logInfo "----------------------------------------------------------------------";
		logInfo "";
		logInfo "Error output from failed command is above.  Exit code was $exitCode";
		logInfo "";
		
		emailLog();
		exit(252);
	}
	
	return @cmdOutput;
}


# Returns ref to hash with info
#		Trailing / are removed
# Uses external COMPRESS_PROG to get information from archive
sub getFullBackupInfo() {
	my $archive = shift;
	
	my %archiveInfo;  # Key is filename, value is mod date (in epoch secs)
	
	
	logInfo "\tGetting full backup information";

	my $runArchiveCmd = qq{"} . COMPRESS_PROG . qq{" l -slt "$archive"};


	logInfo "\tRunning command $runArchiveCmd";
	logInfo "\t\tTime is " . formatDate(time);  # benchmarking
	
	my @cmdOutput = &runArchiveCmd($runArchiveCmd, 1, 0);  # Capture STDERR,  Don't show progress
	
	logInfo "\t\tDone running command.";

	logInfo "\tParsing...";
	logInfo "\t\tTime is " . formatDate(time);  # benchmarking

	for(my $i = 0; $i < @cmdOutput; $i++) {
		my $currLine = $cmdOutput[$i];
		
		if($currLine =~ /^Path\s\=\s(.+)\n/) {
			my $filename = $1;
			$filename =~ s/\\/\//g;  # Convert \ to /

			# Now with p7zip (Linux) the first entry can be the actual archive itself
			# which we know by the second line which may be Type = ...
			my $secondLine = $cmdOutput[$i + 1];
			if(index($secondLine, "Type") != -1) {
				next;  # skip this entry
			}

			# Need to read the next three lines, the third one has the modified date in local locale time
			my $modified = $cmdOutput[$i + 3];
			if(!defined($modified)) {
				logError("Unable to parse modified date for file '$currLine' in archive $archive");
				emailLog();
				exit(255);
			}

			# Need to store the modified date in epoch seconds
			$modified =~ /(\d\d\d\d)-(\d\d)-(\d\d)\s(\d\d):(\d\d):(\d\d)/;
			$archiveInfo{$filename} = timelocal($6, $5, $4, $3, ($2-1), $1);
		} else {
			# print "±";  # Show a little progress bar
		}
	}
	
	logInfo "\tDone parsing.  Time is " . formatDate(time);
	logInfo "";

	return \%archiveInfo;  # Return reference to hash
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


sub emailLog {
	my $emailPriority;
	my $emailSubject;
	
	if($logData =~ /ERROR/) {
		$emailPriority = 1;
		$emailSubject = "ERROR:  ";
	} else {
		$emailPriority = 5;  # low
		$emailSubject = "";
	}
	

	$emailSubject .= "$backupType backup of $fldToBackup log result";
	
	
	my $mimeMessage = MIME::Lite->new(
							From		=> EMAIL_FROM,
							To			=> EMAIL_TO,
							Subject	=> $emailSubject,
							Data		=> $logData,
							"X-Priority" => $emailPriority,
						);
	
	
	# Setup system wide default
	MIME::Lite->send('smtp', +EMAIL_SMTP);
	
	
	eval {
		$mimeMessage->send('smtp', EMAIL_SMTP, Debug=>1);
	};
	
	if($@) {
		open(FH,">","/home/rbeede/BackupFullDiff.email.error.log") or die("$@\n$!\n");
		print FH $@;
		close(FH);
	}
	
	# DEBUG 2010-03-25
	# for some reason this e-mail is never getting received so dump all debug info to a log
	# done via scheduled task > /home/rbeede/log file
}
