#!/usr/bin/perl
#
# Copyright 2011 Rodney Beede
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Rodney Beede
#
use constant VERSION => "2011-06-12";
#
# Takes the new LDS.org CSV export format and converts to vCard which is more friendly for importing into other apps
#


use strict;
use warnings "all";

require 5.012_003;  # tested to work on this version

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


# Libraries
use File::Spec;

# Don't come with Perl distribution by default
use Text::CSV;
use Text::vCard::Addressbook;
use Text::vCard;


main();  # For scoping

sub main {
	if(2 != @ARGV) {
		print STDERR "Usage:  perl $0 <LDS.org csv> <output.vcard>\n";
		exit(255);
	}
	
	my $sourceCSV = File::Spec->rel2abs($ARGV[0]);
	my $destinationVcard = File::Spec->rel2abs($ARGV[1]);
	
	if(-f $sourceCSV && -r $sourceCSV) {
		print "Reading from CSV file at " . $sourceCSV . "\n";
	} else {
		print STDERR "Cannot read from $sourceCSV.  Non-existant file or permission error.\n";
		exit(255);
	}
	
	my $csvParser = Text::CSV->new({ binary => 1 }) or die "Cannot use CSV: ".Text::CSV->error_diag ();
	
	open(my $CSV_FH, "<", $sourceCSV) or die("Unable to open $sourceCSV\n\t$!\n");
	
	my $csvHeaderNames_ArrayRef = $csvParser->getline($CSV_FH);  # First row had headers
	
	$csvParser->column_names($csvHeaderNames_ArrayRef);  # Set column names for hash reference later
	
	# print "Column names are:\n\t";
	# print join("\n\t", @{$csvHeaderNames_ArrayRef});
	# print "\n";
	
	my $totalCount = 0;
	
	my $vCardAddressBook = new Text::vCard::Addressbook();
	
	while(my $row_HashRef = $csvParser->getline_hr($CSV_FH)) {
		my $vcard = $vCardAddressBook->add_vcard();
		
		$vcard->fullname($row_HashRef->{'Couple Name'});
		
		# Find an e-mail, if any
		if($row_HashRef->{'Family Email'}) {
			$vcard->email($row_HashRef->{'Family Email'});
		} elsif($row_HashRef->{'Head Of House Email'}) {
			$vcard->email($row_HashRef->{'Head Of House Email'});
		} elsif($row_HashRef->{'Spouse Email'}) {
			$vcard->email($row_HashRef->{'Spouse Email'});
		}
		
		# Address
		if($row_HashRef->{'Family Address'}) {
			my $address = $vcard->add_node({'node_type'=>'ADR'});
			
			$address->add_types('home');
			# The data is all in one column so we don't try to separate it for now
			# We simply aren't locale aware
			$address->street($row_HashRef->{'Family Address'});
		}
		
		# Phone number
		my $homePhone = $vcard->add_node({'node_type'=>'TEL'});
		$homePhone->add_types('home');
		$homePhone->value($row_HashRef->{'Family Phone'});
		
		if($row_HashRef->{'Head Of House Phone'}) {
			my $alternativePhone = $vcard->add_node({'node_type'=>'TEL'});
			$alternativePhone->add_types('Head Of House Phone');
			#$alternativePhone->add_types('other');
			$alternativePhone->value($row_HashRef->{'Head Of House Phone'});
		}
		if($row_HashRef->{'Spouse Phone'}) {
			my $alternativePhone = $vcard->add_node({'node_type'=>'TEL'});
			$alternativePhone->add_types('Spouse Phone');
			#$alternativePhone->add_types('other');
			$alternativePhone->value($row_HashRef->{'Spouse Phone'});
		}		
		
		
		$totalCount++;
	}
	
	close($CSV_FH);
	
	
	open(my $VCARD_FH, ">", $destinationVcard) or die("$!\n");
	
	print $VCARD_FH $vCardAddressBook->export();
	
	close($VCARD_FH);
	
	print "Wrote $destinationVcard\n";
	
	
	print "Total number of entries was $totalCount\n";
}
