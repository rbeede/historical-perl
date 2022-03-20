#
# Author:  Rodney Beede
#
use constant VERSION => "2011-04-30";
#
# Tested with Perl 5.12
#
# ffmpeg-r22941-swscale-r31050-mingw-w64-static
#	Windows 64-bit
#
# Takes MPEG2 TS (transport stream) container video and audio
#	Video Codec:	MPEG2
#	Audio Codec:	MPEG2
# and converts it to an AVI container
#	Video Codec:	HuffYUV
#	Audio Codec:	PCM S16 LE
#
# Recommend the use of VirtualDub (http://www.virtualdub.org/) for editing afterwards
#
# Recommend the use of VideoLan (http://www.videolan.org/) for playing either format
#
#


use strict;
use warnings "all";

use File::Find;


use constant CONVERT_COMMAND => qq{"ffmpeg" -i "INSERT SOURCE" -vcodec huffyuv -acodec pcm_s16le "INSERT DESTINATION"};


my $scriptDirectory = File::Basename::dirname(File::Spec->rel2abs($0));
my $scriptFilename = File::Basename::basename(File::Spec->rel2abs($0));


main();  # scoping


sub main {
	if(@ARGV != 2) {
		usage();
		exit(0);
	}
	
	my $sourceDirectory = $ARGV[0];
	my $destinationDirectory = $ARGV[1];
	
	if(! -d $sourceDirectory) {
		print STDERR "$sourceDirectory is not a directory!\n";
		exit(255);
	} elsif(-e $destinationDirectory && ! -d $destinationDirectory) {
		print STDERR "$destinationDirectory exists, but is not a directory!\n";
		exit(255);
	} else {
		print "Using source directory of $sourceDirectory and outputing to destination directory of $destinationDirectory\n";
		print "\n";
	}
	
	
	# Find ffmpeg binary in sub-directory of this script file
	my $ffmpegBinary;
	find(sub {
			if($_ =~ m/ffmpeg.exe$|ffmpeg$/ && -f -x $File::Find::name) {
				$ffmpegBinary = $File::Find::name;
				return;
			}
		},
		$scriptDirectory);
		
	print "Using $ffmpegBinary\n";
	print "\n";
	
	
	opendir(SRC_DH, $sourceDirectory) or die("Unable to open $sourceDirectory\n\t$!\n");
	
	while($_ = readdir(SRC_DH)) {
		my $currSourceFullPathname = $sourceDirectory . "/" . $_;
		
		if(! -f $currSourceFullPathname || $currSourceFullPathname !~ m/\.ts$/i) {
			next;  # skip non-video files
		}
		
		print "Processing $currSourceFullPathname...\n";
		
		my $destFullPathname = $destinationDirectory . "/" . $_;
		$destFullPathname =~ s/\.ts$/; HuffYUV, PCM S16 LE, AVI.avi/i;
		
		print "\tDestination pathname is $destFullPathname\n";
		
		my $currCmd = CONVERT_COMMAND;
		$currCmd =~ s/ffmpeg/$ffmpegBinary/;
		$currCmd =~ s/INSERT SOURCE/$currSourceFullPathname/;
		$currCmd =~ s/INSERT DESTINATION/$destFullPathname/;
		
		print "\tRunning command $currCmd";
		
		if(0 != (system($currCmd) >> 8)) {
			print STDERR "Command failed with error exit code\n";
		}
	}
	
	closedir(SRC_DH);
}


sub usage {
	print "perl $scriptFilename /path/to/src/dir/ /path/to/dest/dir/\n";
	print "\n";
}
