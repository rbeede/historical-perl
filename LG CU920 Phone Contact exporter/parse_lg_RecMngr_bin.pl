# Author:  Rodney Beede
# Version:  2011-10-30
# Copyright 2011
#
# License:  GNU GPL version 3


use strict;

use 5.010;

use Fcntl;

main();  # for scoping

sub main {
	my $recMngrBinFile = $ARGV[0];
	
	if(!defined($recMngrBinFile) || ! -r $recMngrBinFile) {
		die("Could not read RecMngr.bin or not provided!\nUsage: perl $0 /path/to/RecMngr.bin\n");
	}
	
	sysopen(my $binaryFH, $recMngrBinFile, O_RDONLY) or die("$!\n");
	
	my @fileBytes;
	
	print "Reading in bytes via sysread\n";
	sysread $binaryFH, my $buffer, -s $recMngrBinFile;
	close $binaryFH;
	print "Done reading bytes\n";
	
	print "Unpacking bytes at\t" . localtime(time()) . "\n";
	@fileBytes = unpack("H2" x (-s $recMngrBinFile), $buffer);
	print "Finished unpacking bytes at " . localtime(time()) . "\n";
	

	
	
	print "Number of byte read was " . (scalar @fileBytes) . "\n";
	
	
	# Store in hash so we can pretty print later
	my %contactsList;  # {name} = phone number
	
	# Loop through each byte
	for(my $i = 0; $i < (scalar @fileBytes); $i++) {
		# 7c 00 00 ff ff	is our magic sequence for start of contact
		if(hex($fileBytes[$i]) == 0x7c) {
			if(hex($fileBytes[$i+1]) == 0x00 && hex($fileBytes[$i+2]) == 0x00 && hex($fileBytes[$i+3]) == 0xff && hex($fileBytes[$i+4]) == 0xff) {
				# Found one (possibly)
				#	Could also be an MMS or other entry
				# 96 bytes later should have sequence 00 00 00 01
				# After those 4 bytes would be the start of the big-endian unicode phone number
				my $checkSequence = join(' ', @fileBytes[($i+96)..($i+99)]);
				if($checkSequence ne '00 00 00 01') {
					print "Skipping non-phone entry:\t" . $checkSequence . "\n";
					next;
				}
				
				# Phone number (if any) starts 100 bytes later
				# It is variable length since it can include + or other characters
				# It ends when we see two 00's in a row
				my $phoneOffset = $i + 100;
				# We just pull 30 bytes worth (15 chars) to get it
				my $phoneOffsetEnd = $phoneOffset + 30;
				
				
				my @phoneBytes = @fileBytes[$phoneOffset..$phoneOffsetEnd];
				print "Phone bytes are:\t" . join(' ', @phoneBytes) . "\n";
				
				# Convert big-endian unicode into phone number characters (we dumb down to ASCII)
				my $phoneNumberString = "";
				for(my $j = 0; $j < @phoneBytes; $j++) {
					if(hex($phoneBytes[$j]) != 0x00) {
						$phoneNumberString .= chr(hex($phoneBytes[$j]));
					}
				}
				
				print "Phone number string is |||" . $phoneNumberString . "|||\n";
				
				
				# Now we need to get the contact name
				# Name starts at 546 bytes after start of record marker
				# End of name is signaled by two 00 00
				my $contactNameOffset = $i + 546;
				my $contactNameEnd = -1;
				
				for(my $j = $contactNameOffset; $j < ($contactNameOffset + 255); $j++) {  # the + 255 is just a sanity check in case we miss the 00 00 sequence
					if(hex($fileBytes[$j]) == 0x00 && hex($fileBytes[$j+1]) == 0x00) {
						$contactNameEnd = $j;
						last;
					}
				}
				if(-1 == $contactNameEnd) {
					die("Never found end of contact name for phone number $phoneNumberString\n");
				}
				
				# Convert big-endian unicode into contact name characters (we dumb down to ASCII)
				my $contactName = "";
				for(my $j = $contactNameOffset; $j < $contactNameEnd; $j++) {
					if(hex($fileBytes[$j]) != 0x00) {
						$contactName .= chr(hex($fileBytes[$j]));
					}
				}
				
				print "Contact name is |||" . $contactName . "|||\n";

				$contactsList{$contactName} = $phoneNumberString;
			}
		}
	}
	
	
	# Output pretty results in CSV format
	print "\n\n";
	
	print "Full Name,Phone Number\n";
	foreach my $name (keys %contactsList) {
		print $name;
		print ',';
		print $contactsList{$name};  # phone number
		print "\n";
	}
	
	print "\n";

}
