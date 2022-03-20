#!/usr/bin/perl
#
# Rodney Beede
#
my $VERSION = "2013-10-02";
#
#


use strict;
use warnings /ALL/;



# For now hard-coded commands, maybe in future command line argument to file with list of commands
my @runAndWaitCommands =	(
								q{c:\\Users\\rbeede\\Software\\md5deep-4.4\\md5deep64 -r -z -c -j0 R:\\ > C:\\Users\\rbeede\\Desktop\\r_drive.csv},
								q{c:\\Users\\rbeede\\Software\\md5deep-4.4\\md5deep64 -r -z -c -j0 B:\\ > C:\\Users\\rbeede\\Desktop\\B_drive.csv},
							);

# Processed sequentially in order
my @lastCommands =	(
						q{perl R:\\Rodneys_Backup\\Backup_Tools\\HashAndVerifyBackups\\VerifyHashes.pl C:\\Users\\rbeede\\Desktop\\r_drive.csv C:\\Users\\rbeede\\Desktop\\B_drive.csv},
						q{cmd /c move R:\\Rodneys_Backup\\Backup_Tools\\HashAndVerifyBackups\\Report.tsv C:\\Users\\rbeede\\Desktop},
						q{shutdown /s /t 60 /c "Hashing complete" /d p:0:0},
					);
							

main(@ARGV);


sub main {
	my @pids;
	
	
	foreach my $command (@runAndWaitCommands) {
		my $pid = fork();
		if($pid) {
			# Parent
			push @pids, $pid;
		} elsif(0 == $pid) {
			# Child
			print "Executing command:  $command\n";
			
			exec $command;  # Never returns
			
			# Not needed unless we change code later, helps prevent accidental omission if code changes
			exit 0;
		} else {
			# fork call failed
			die("Could not fork:  $!\n");
		}
	}
	
	
	# Now wait and block for each command to finish
	print "Waiting for commands to complete...\n";
	foreach my $pid (@pids) {
		waitpid($pid, 0);
		print "PID $pid has finished\n";
	}
	
	
	# Now run the last commands
	print "Running last commands:\n";
	foreach my $lastCmd (@lastCommands) {
		print "\t" . $lastCmd . "\n";
		system($lastCmd);
	}
}
