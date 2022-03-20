# Rodney Beede
# 2012-11-04
# First version:  2009-04-13

use strict;

# Load private lib folder
BEGIN {
	use File::Basename;
	use File::Spec;
	
	my $scriptLoc = File::Spec->rel2abs($0);
	$scriptLoc = dirname($scriptLoc);
	
	$scriptLoc =~ s/\\/\//g;
	
	push @INC, "$scriptLoc/lib";
}


use Image::MetaData::JPEG;
use File::Find;
use File::stat;
use File::Spec;


# Force STDOUT to flush
my $old_handle = select (STDOUT);	# "select" STDOUT and save previously selected handle
$| = 1; # perform flush after each write to STDOUT
select ($old_handle); # restore previously selected handle



main();  # force some scoping


sub main {
	if(1 != @ARGV) {
		print "Usage:  perl $0 <directory to recurse for jpg>\n";
		print "\n";
		print "Output is written to STDOUT in tab delimited form.\n";
		print "\n";
		exit(1);
	}
	

	my $PHOTO_DIR = File::Spec->rel2abs($ARGV[0]);
	if(! -d $PHOTO_DIR) {
		print STDERR "$PHOTO_DIR is not a directory!\n";
		exit(255);
	}

	print STDERR "Scanning directory $PHOTO_DIR\n";
	print STDERR "\n";
	

	# Tab delimited header
	print "Valid\tPathname\tByte Size\tDimensions\n";


	find(	sub {
				my $directoryname = $File::Find::dir;	# current directory (absolute)
				my $filename = $_;						# filename part only
				my $pathname = $File::Find::name;		# absolute path and filename
				
				if(-d $pathname) {  return;  }  # A directory isn't a jpg so avoid dirname.jpg edge case
				if($filename !~ /\.jpg$/i) {  return;  }  # doesn't end in .jpg (case insensitive)

				my $jpegfile = new Image::MetaData::JPEG($pathname);
				if(! $jpegfile) {
					# Found a problem while parsing the jpeg file
					print "NO";
				} else {
					print "yes";
				}
				print "\t";
				
				print "$pathname";
				print "\t";
				
				# Size of file in bytes
				print stat($pathname)->size;
				print "\t";
				
				if(! $jpegfile) {
					my $errmsg = Image::MetaData::JPEG::Error();
					$errmsg =~ s/[\r\n]*/, /g;
					print "$errmsg";
				} else {
					# Get the JPEG picture dimensions
					my ($dim_x, $dim_y) = $jpegfile->get_dimensions();
					print "$dim_x by $dim_y";
				}
				
				print "\n";
			}  # end of anonymous sub

		# Closing part of find
		, $PHOTO_DIR);

	print STDERR "Scan complete.\n";
}  # end of main
