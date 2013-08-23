#!/usr/bin/perl
use strict;

use OpenSRF::System;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::JSON;
use FileHandle;
use Data::Dumper;

use Time::HiRes qw/time/;
use Getopt::Long;

my @files;
my ($config, $output, @auto, @order, @wipe, $quiet) =
	('/openils/conf/opensrf_core.xml');
my $nocommit = 0;

GetOptions( 'config=s'	    => \$config,
            'output=s'	    => \$output,
            'wipe=s'	    => \@wipe,
            'autoprimary=s' => \@auto,
            'order=s'	    => \@order,
            'nocommit|n'    => \$nocommit,
            'quiet'         => \$quiet,
);

my %lineset;
my %fieldcache;

OpenSRF::System->bootstrap_client( config_file => $config );
Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

my $count = 0;
my $starttime = time;

print STDERR "\nWriting file ...\n" if (!$quiet);

$output = '&STDOUT' unless ($output);
$output = FileHandle->new(">$output") if ($output);

binmode($output,'utf8');

$output->print("SET CLIENT_ENCODING TO 'UNICODE';\n\n");
$output->print("BEGIN;\n\n");

while ( my $rec = <> ) {
	next unless ($rec);

	

	my $row;
	try {
		$row = OpenSRF::Utils::JSON->JSON2perl($rec);
	} catch Error with {
		my $e = shift;
		warn "\n\n !!! Error : $e \n\n at or around line $count\n";
		print STDERR "\nSomething went wrong...\n";
	};
	next unless ($row);

	my $class = $row->class_name;
	my $hint = $row->json_hint;
	
	# active,create_date,creator,deleted,edit_date,editor,fingerprint,id,
	#last_xact_id,marc,quality,source,tcn_source,tcn_value,owner,share_depth';
	
	my $marc = $row->marc;
	$marc =~ s/\f/\\f/gos;
	$marc =~ s/\n/\\n/gos;
	$marc =~ s/\r/\\r/gos;
	$marc =~ s/\t/\\t/gos;
	$marc =~ s/\\/\\\\/gos;

	print STDERR "\n" . $row->tcn_value;
	$output->print("INSERT INTO biblio.record_entry (marc, last_xact_id) VALUES (\$BOOGADYBOOOGADYBOOOO\$"
	.$marc
	."\$BOOGADYBOOOGADYBOOOO\$, 'kyle');\n");

	if (!$quiet && !($count % 500)) {
		
		print STDERR "\r$count\t". $count / (time - $starttime);
	}

	$count++;
}




my $after_commit = '';
for my $h (@order) {
	
	
	
	# continue if there was no data for this table
	next unless ($fieldcache{$h});
	
	

	my $fields = join(',', @{ $fieldcache{$h}{fields} });
	$output->print( "DELETE FROM $fieldcache{$h}{table};\n" ) if (grep {$_ eq $h } @wipe);
	# Speed up loading of bib records
	$output->print( "COPY $fieldcache{$h}{table} ($fields) FROM STDIN;\n" );

	for my $line (@{ $lineset{$h} }) {
		my @data;
		my $x = 0;
		
		for my $d (@$line) {
			if (!defined($d)) {
				$d = '\N';
			} else {
				$d =~ s/\f/\\f/gos;
				$d =~ s/\n/\\n/gos;
				$d =~ s/\r/\\r/gos;
				$d =~ s/\t/\\t/gos;
				$d =~ s/\\/\\\\/gos;
			}
			if ($h eq 'bre' and $fieldcache{$h}{fields}[$x] eq 'quality') {
				$d = int($d) if ($d ne '\N');
			}
			push @data, $d;
			$x++;
		}
		$output->print( join("\t", @data)."\n" );
	}

	$output->print('\.'."\n\n");
	
	if ($h eq 'mfr') {
		$output->print("SELECT reporter.enable_materialized_simple_record_trigger();\n");
		$output->print("SELECT reporter.disable_materialized_simple_record_trigger();\n");
	}

	$after_commit .= "SELECT setval('$fieldcache{$h}{sequence}'::TEXT, (SELECT MAX($fieldcache{$h}{pkey}) FROM $fieldcache{$h}{table}), TRUE);\n"
		if (!grep { $_ eq $h} @auto);
}

$output->print("COMMIT;\n\n") unless $nocommit;
$output->print($after_commit);
$output->close; 
