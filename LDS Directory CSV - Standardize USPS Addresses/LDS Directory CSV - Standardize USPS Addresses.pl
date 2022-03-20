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
# Takes the new LDS.org CSV export format and outputs the couple name and address in USPS standard format
# Uses USPS.com Zip Code finder to check the addresses
# Also takes any phone numbers and puts them into standard format (###) ###-####
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
use HTTP::Request::Common qw(POST);
use LWP::UserAgent;

# Don't come with Perl distribution by default
use Text::CSV;
use Geo::StreetAddress::US;


main();  # For scoping

sub main {
	if(2 != @ARGV) {
		print STDERR "Usage:  perl $0 <LDS.org csv> <output.csv>\n";
		exit(255);
	}
	
	my $sourceCSV = File::Spec->rel2abs($ARGV[0]);
	my $destinationCSV = File::Spec->rel2abs($ARGV[1]);
	
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
	
	open(my $DEST_FH, ">:encoding(utf8)", $destinationCSV) or die("Unable to open $destinationCSV for writing:\t$!\n");
	
	$csvParser->print($DEST_FH, ['Couple Name', 'Street Address', 'City', 'State', 'Zip', 'Family Phone', 'Head Of House Phone', 'Spouse Phone']);
	print $DEST_FH "\n";
	
	while(my $row_HashRef = $csvParser->getline_hr($CSV_FH)) {
		my $newRow_ArrayRef;
		
		$newRow_ArrayRef->[0] = trim($row_HashRef->{'Couple Name'});
		
		# LDS.org doesn't separate out the address components so we have to ourself
		my $pa = Geo::StreetAddress::US->parse_location($row_HashRef->{'Family Address'});
		$newRow_ArrayRef->[1] = "";
		if($pa->{'number'}) {
			$newRow_ArrayRef->[1] .= $pa->{'number'};
			$newRow_ArrayRef->[1] .= " ";
		}
		if($pa->{'street'}) {
			$newRow_ArrayRef->[1] .= $pa->{'street'};
			$newRow_ArrayRef->[1] .= " ";
		}
		if($pa->{'type'}) {
			$newRow_ArrayRef->[1] .= $pa->{'type'};
			$newRow_ArrayRef->[1] .= " ";
		}
		if($pa->{'suffix'}) {
			$newRow_ArrayRef->[1] .= $pa->{'suffix'};
			$newRow_ArrayRef->[1] .= " ";
		}
		if($pa->{'sec_unit_type'}) {
			$newRow_ArrayRef->[1] .= $pa->{'sec_unit_type'};
			$newRow_ArrayRef->[1] .= " ";
		}
		if($pa->{'sec_unit_num'}) {
			$newRow_ArrayRef->[1] .= $pa->{'sec_unit_num'};
			$newRow_ArrayRef->[1] .= " ";
		}
		$newRow_ArrayRef->[1] = trim($newRow_ArrayRef->[1]);

		$newRow_ArrayRef->[2] = uppercase($pa->{'city'});
		$newRow_ArrayRef->[3] = uppercase($pa->{'state'});
		$newRow_ArrayRef->[4] = $pa->{'zip'};
		
		# Query USPS for better address format
		($newRow_ArrayRef->[1], $newRow_ArrayRef->[4]) = queryUSPS($newRow_ArrayRef->[1], $newRow_ArrayRef->[2], $newRow_ArrayRef->[3]);
		
					
		# Phone number
		$newRow_ArrayRef->[5] = standardizePhoneNumber($row_HashRef->{'Family Phone'});
		$newRow_ArrayRef->[6] = standardizePhoneNumber($row_HashRef->{'Head Of House Phone'});
		$newRow_ArrayRef->[7] = standardizePhoneNumber($row_HashRef->{'Spouse Phone'});
		
		$csvParser->print($DEST_FH, $newRow_ArrayRef);
		print $DEST_FH "\n";
		
		$totalCount++;
	}
	
	close($DEST_FH);
	close($CSV_FH);
	
	
	print "Total number of entries was $totalCount\n";
}


# U.S.A phone numbers only
sub standardizePhoneNumber {
	my $rawPhoneNumber = shift;
	
	if(!defined($rawPhoneNumber)) {
		return $rawPhoneNumber;
	}
	
	$rawPhoneNumber =~ s/[^0-9]//g;  # remove all non-digits
	
	my $area;
	my $exchange;
	my $line;
	if(length($rawPhoneNumber) >= 10) {
		($area, $exchange, $line) = $rawPhoneNumber =~ m/[1]?(\d{3})(\d{3})(\d{4})/;
	} elsif(length($rawPhoneNumber) == 7) {
		$area = "";
		($exchange, $line) = $rawPhoneNumber =~ m/(\d{3})(\d{4})/;
	} else {
		return $rawPhoneNumber;
	}
	
	return "($area) $exchange-$line";
}


sub trim {
	my $string = shift;
	
	if(!defined($string)) {
		return $string;
	}
	
	# benchmarks show that two separate regex are faster
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	
	return $string;
}


# Handles undef strings safely
sub uppercase {
	my $string = shift;
	
	if(!defined($string)) {
		return $string;
	}
	
	return uc($string);
}


sub queryUSPS {
	my $street = shift;
	my $city = shift;
	my $state = shift;
	
	my $zip = "";
	
	
	my $ua = LWP::UserAgent->new;
	$ua->default_header(Referer => 'http://zip4.usps.com/zip4/welcome.jsp', Origin => 'http://zip4.usps.com',
		'User-Agent' => 'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/534.30 (KHTML, like Gecko) Chrome/12.0.742.91 Safari/534.30',
		);
	
	my $req = POST 'http://zip4.usps.com/zip4/zcl_0_results.jsp',
              [ visited => '1', pagenumber =>'0',address2 => $street,address1 => '',city => $city,
				state => $state,urbanization => '',zip5 => '','submit.x' => '42','submit.y' => '11',
				submit => 'Find ZIP Code', firmname => '',
			  ];
 
 
	my $content = $ua->request($req)->as_string;
	

	my $idx = index($content, '<td headers="full"');
	
	if(-1 == $idx) {
		return ($street, "NO USPS DATA");
	}
	
	$idx = index($content, '>', $idx);
	
	if(-1 == $idx) {
		return ($street, "NO USPS DATA");
	}

	$idx++;  # pass over '>'
	
	my $endIdx = index($content, '<br />', $idx);
	
	if(-1 == $endIdx) {
		return ($street, "NO USPS DATA");
	}
	
	
	$street = substr($content, $idx, $endIdx - $idx);
	$street = trim($street);
	
	
	$idx = index($content, '&nbsp;&nbsp;', $endIdx + length('<br />'));
	if(-1 == $idx) {
		return ($street, "NO USPS DATA");
	}
	
	$endIdx = index($content, '<br />', $idx);
		if(-1 == $endIdx) {
		return ($street, "NO USPS DATA");
	}
	
	$idx += length('&nbsp;&nbsp;');
	
	$zip = substr($content, $idx, $endIdx - $idx);
	$zip = trim($zip);
	
	
	return ($street, $zip);
}
