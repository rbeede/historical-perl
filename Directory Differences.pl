#
# 2011-05-23
#
# $0 <directory full pathname>
#


require 5.10.0;

use strict;
use warnings;

use IO::Handle;
use File::Find;
use Digest::MD5;


##################
# Global variables

##################
# Prototypes



#######
main();  # For better scoping


sub main {
	if(@ARGV < 2) {
		print "$0 \"<directory A>\" \"<directory B>\" [--deep]\n";
		exit(1);
	}
	
	
	my $directoryA = $ARGV[0];
	my $directoryB = $ARGV[1];
	my $deep = $ARGV[2] or 0;
	
	
	if(! -d $directoryA) {
		die("$directoryA is not a directory!\n");
	} elsif(! -d $directoryB) {
		die("$directoryB is not a directory!\n");
	}

	
	print "$directoryA\t$directoryB\tSizeA\tSizeB\tLastModA\tLastModB\tHash Difference?\n";
	
	my %directoryAmetadata;
	getFileTreeMetadata(\%directoryAmetadata, $directoryA, $deep);
	
	my %directoryBmetadata;
	getFileTreeMetadata(\%directoryBmetadata, $directoryB, $deep);
	

	# Compare all the metadata
	foreach my $dirA (sort keys %directoryAmetadata) {
		if(!defined($directoryBmetadata{$dirA})) {
			print $dirA;
			print "\t";
			print "NON EXISTANT";
			print "\t";
			print $directoryAmetadata{$dirA}{'Byte Size'};
			print "\t";
			print "";
			print "\t";
			print $directoryAmetadata{$dirA}{'Last Modification Unix Epoch'};
			print "\t";
			print "";
			print "\t";
			if($deep) {
				print "false";
			} else {
				print "Not Tested";
			}
			print "\n";
		} elsif(
				$directoryAmetadata{$dirA}{'Byte Size'} != $directoryBmetadata{$dirA}{'Byte Size'}
					||
				$directoryAmetadata{$dirA}{'Last Modification Unix Epoch'} != $directoryBmetadata{$dirA}{'Last Modification Unix Epoch'}
					||
				($deep && $directoryAmetadata{$dirA}{'Hash Code'} ne $directoryBmetadata{$dirA}{'Hash Code'})
			) {
			print $dirA;
			print "\t";
			print $dirA;
			print "\t";
			print $directoryAmetadata{$dirA}{'Byte Size'};
			print "\t";
			print $directoryBmetadata{$dirA}{'Byte Size'};
			print "\t";
			print $directoryAmetadata{$dirA}{'Last Modification Unix Epoch'};
			print "\t";
			print $directoryBmetadata{$dirA}{'Last Modification Unix Epoch'};
			print "\t";
			if($deep) {
				if($directoryAmetadata{$dirA}{'Hash Code'} ne $directoryBmetadata{$dirA}{'Hash Code'}) {
					print "true";
				} else {
					print "false";
				}
			} else {
				print "Not Tested";
			}
			print "\n";
		}
	}
	
	# go through directoryBmetadata to get non-existing in directoryAmetadata
	foreach my $dirB (keys %directoryBmetadata) {
		if(!defined($directoryAmetadata{$dirB})) {
			print "NON EXISTANT";
			print "\t";
			print $dirB;
			print "\t";
			print "";
			print "\t";
			print $directoryBmetadata{$dirB}{'Byte Size'};
			print "\t";
			print "";
			print "\t";
			print $directoryBmetadata{$dirB}{'Last Modification Unix Epoch'};
			print "\t";
			if($deep) {
				print "false";
			} else {
				print "Not Tested";
			}
			print "\n";
		}
	}
}


# Returns:  No return, inline modification
# First param:  Hash with  {full pathname of file}	->	{Byte Size} = bytes
#											->	{Last Modification Unix Epoch} = epoch seconds
#											->	{Hash Code} = if deep != false then has hash
#	Hash is modified and passed recursively as needed
sub getFileTreeMetadata {
	my $metadata = $_[0];
	my $directory = $_[1];
	my $deep = $_[2] or 0;
	
	my $treeroot = (defined($_[3]) ? $_[3] : $directory);  # You don't have to set this, it is automatic

	# Standardize the /
	$directory =~ s/\\/\//g;	# \ to /


	# To prevent opening too many stream handles we record children entries that are directories
	#	for recursive search later
	my $streamHandle;
	if(!opendir($streamHandle, "$directory")) {
		if($! eq "Invalid argument" && $^O =~ m/MsWin/i) {
			# Known issue under Windows 7 (Vista/XP) where a Junction (like a hard link) has permissions restricted
			#	so that opendir fails.
			#	See http://www.rodneybeede.com/Perl_issues_with_opendir__or_File__Find__on_Windows_file_systems_with_Junction_directories.html
			return;
		} else {
			die("$directory\t$!\n");
		}
	}
	
	my @childrenDirectories;
	
	while(readdir($streamHandle)) {
		my $fullPath = $directory . "/" . $_;
		
		
		if("." eq $_ || ".." eq $_ || -l $fullPath) {
			# Skip over symbolic links
			next;
		}
		
		# symbolic links are not followed nor checked
		if(-d $fullPath && ! -l $fullPath) {
			push @childrenDirectories, $fullPath;
			next;
		}
		
		# Get our file entry with the tree root removed
		my $fileEntry = substr($fullPath, length($treeroot));
		
		$metadata->{$fileEntry}->{'Byte Size'} = (stat($fullPath))[7];
		$metadata->{$fileEntry}->{'Last Modification Unix Epoch'} = (stat($fullPath))[9];
		if($deep) {
			$metadata->{$fileEntry}->{'Hash Code'} = digestFile($fullPath);
		} else {
			$metadata->{$fileEntry}->{'Hash Code'} = undef;
		}
	}
	
	close($streamHandle);
	
	
	foreach my $childDirectory (@childrenDirectories) {
		getFileTreeMetadata($metadata, $childDirectory, $deep, $treeroot);
	}
}


sub digestFile {
	my $fullPath = shift;
	
	
	my $digest;
	
	if(!open(FH, "<", $fullPath)) {
		print STDERR $fullPath;
		print STDERR "\t";
		print STDERR "$!";
		print STDERR "\n";
		return;
	}
	binmode(FH);
	
	$digest = Digest::MD5->new->addfile(*FH)->hexdigest;
	
	close(FH);
	
	
	return $digest;
}
