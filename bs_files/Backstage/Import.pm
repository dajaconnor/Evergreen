# ---------------------------------------------------------------
# Copyright © 2012 Merrimack Valley Library Consortium
# Jason Stephenson <jstephenson@mvlc.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
package Backstage::Import;

use strict;
use warnings;

use Carp;
use MARC::Record;
use MARC::File::XML;
use MARC::File::USMARC;
use OpenILS::Utils::Cronscript;
use OpenILS::Utils::Normalize qw(clean_marc);
use DateTime;
use DateTime::Format::ISO8601;
use Encode;

my $U = 'OpenILS::Application::AppUtils';

sub new {
    my $class = shift;
    my $self = {};
    $self->{'prefs'} = shift;
    $self->{'rerun'} = shift;
    $self->{'utf8'} = 0;
    my $dstr = $self->{'prefs'}->export->last_run_date;
    $dstr =~ s/ /T/;
    $dstr =~ s/\.\d+//;
    $dstr =~ s/([-+]\d\d)\d\d$/$1/;
    $self->{'export_date'} = DateTime::Format::ISO8601->parse_datetime($dstr);
    $self->{'bibs'} = [];
    $self->{'new_auths'} = 0;
    bless($self, $class);
    return $self;
}

sub doFile {
    print("Inside doFile\n");
    my $self = shift;
    my $filename = shift;
    my $isUTF8 = (($filename =~ /\.UTF8$/) || $self->{'utf8'});
    my $file = MARC::File::USMARC->in($filename, ($isUTF8) ? 'UTF8' : undef);
    if ($file) {
        $self->{'scr'} = OpenILS::Utils::Cronscript->new({nolockfile=>1});
        $self->{'auth'} = $self->{'scr'}->authenticate(
            $self->{'prefs'}->evergreen->authentication->TO_JSON
        );
        print("Filename: " . $filename . "\n");
        if ($filename =~ /BIB/) {
            $self->doBibs($file);
        } elsif ($filename =~ /DEL/) {
            $self->doDeletes($file);
        } elsif ($filename =~ /AUTH/) {
            $self->doAuths($file);
        }
        $file->close();
        $self->{'scr'}->logout;
    } else {
        carp "Failed to read MARC from $filename.";
    }
}

sub doBibs {
    print("Inside doBibs\n");
    my $self = shift;
    my $file = shift;
    my $editor = $self->{'scr'}->editor(authtoken=>$self->{'auth'});
    print("start while in doBibs\n");
    while (my $input = $file->next()) {
        my $id = $input->subfield('901', 'c');
        print ("id = " . $id . "\n");
        if ($id) {
            my $bre = $editor->retrieve_biblio_record_entry($id);
            print("bre = " . $bre . "\n");
            next if (!$bre || $U->is_true($bre->deleted));
            my $record = MARC::Record->new_from_xml($bre->marc, 'UTF8');
            my $str = $bre->edit_date;
            $str =~ s/\d\d$//;
            my $edit_date = DateTime::Format::ISO8601->parse_datetime($str);
            print("export_date = " . $self->{'export_date'} . "\n");
            if (DateTime->compare($edit_date, $self->{'export_date'}) < 0) {
                my $needImport = date_comp($input, $record);
                if ($needImport > 0) {
                    print("Import $id\n")
                        if ($self->{'prefs'}->get('import')->print_import);
                    my $newMARC = $input->as_xml_record();
                    $bre->marc(clean_marc($newMARC));
                    $bre->edit_date('now()');
                    $editor->xact_begin;
                    $editor->update_biblio_record_entry($bre);
                    $editor->commit;
                    push(@{$self->{'bibs'}}, $id);
                } else {
                    print("Keep $id\n")
                        if ($self->{'prefs'}->get('import')->print_keep);
                }
            }
        } else {
            carp "No 901\$c in input record $id";
        }
    }
    $editor->finish;
}

sub doDeletes {
    my $self = shift;
    my $file = shift;
    my $editor = $self->{'scr'}->editor(authtoken=>$self->{'auth'});
    while (my $input = $file->next()) {
        my @ares = find_matching_ares($editor, $input);
        if (scalar @ares) {
            $editor->xact_begin;
            foreach my $are (@ares) {
                print("Deleting auth " . $are->id . "\n")
                    if ($self->{'prefs'}->get('import')->print_delete);
                $editor->delete_authority_record_entry($are);
            }
            $editor->commit;
        }
    }
    $editor->finish;
}

sub doAuths {
    print("Inside doAuths\n");
    my $self = shift;
    my $file = shift;
    my $editor = $self->{'scr'}->editor(authtoken=>$self->{'auth'});
    while (my $input = $file->next()) {
        my @ares = find_matching_ares($editor, $input);
        if (scalar(@ares)) {
            foreach my $are (@ares) {
                my $record = MARC::Record->new_from_xml($are->marc, 'UTF8');
                if (!$self->{'rerun'} ||
                        ($self->{'rerun'} && date_comp($input, $record))) {
                    $editor->xact_begin;
                    print("Updating auth: " . $are->id . "\n")
                        if ($self->{'prefs'}->get('import')->print_import);
                    my $newMARC = $input->as_xml_record();
                    $are->marc(clean_marc($newMARC));
                    $are->edit_date('now()');
                    $editor->update_authority_record_entry($are);
                    $editor->commit;
                }
            }
        } else {
            $editor->xact_begin;
            my $are = Fieldmapper::authority::record_entry->new();
            my $marc = $input->as_xml_record();
            $are->marc(clean_marc($marc));
            $are->last_xact_id("IMPORT-" . time);
            $are->source(2);
            if ($are = $editor->create_authority_record_entry($are)) {
                print("Created new auth " . $are->id . "\n")
                    if ($self->{'prefs'}->get('import')->print_import);
                $self->{'new_auths'}++;
            } else {
                carp("Failed to create new auth\n");
            }
            $editor->commit;
        }
    }
    $editor->finish;
}

sub utf8 {
    my $self = shift;
    if (@_) {
        $self->{'utf8'} = shift;
    }
    return $self->{'utf8'};
}

sub rerun {
    my $self = shift;
    if (@_) {
        $self->{'rerun'} = shift;
    }
    return $self->{'rerun'};
}

# read only property.
sub bibs {
    my $self = shift;
    return $self->{'bibs'};
}

sub have_new_auths {
    my $self = shift;
    return $self->{'new_auths'};
}

sub find_matching_ares {
    my $e = shift;
    my $rec = shift;
    my @results = ();
    my $afrs = [];
    my $subfield = $rec->subfield('010', 'a');
    if ($subfield) {
        $afrs = $e->search_authority_full_rec(
            {
                'tag' => '010',
                'subfield' => 'a',
                'value' => { "=" => ['naco_normalize', $subfield, 'a'] }
            }
        );
        foreach my $afr (@$afrs) {
            push(@results, $e->retrieve_authority_record_entry($afr->record));
        }
    } elsif ($subfield = $rec->subfield('035', 'a')) {
        $afrs = $e->search_authority_full_rec(
            {
                'tag' => '035',
                'subfield' => 'a',
                'value' => { "=" => ['naco_normalize', $subfield, 'a'] }
            }
        );
        foreach my $afr (@$afrs) {
            push(@results, $e->retrieve_authority_record_entry($afr->record));
        }
    }
    return @results;
}

sub fix005 {
    my $in = shift;
    substr($in,8,0) = 'T';
    $in =~ s/\.0$//;
    return $in;
}

sub date_comp {
    my ($bslw, $own) = @_;
    my $bslw_date = undef;
    my $rec_date = undef;
    my $need_import = 1;

    $bslw_date = DateTime::Format::ISO8601->parse_datetime(
        fix005($bslw->field('005')->data())
    ) if (defined($bslw->field('005')));

    $rec_date = DateTime::Format::ISO8601->parse_datetime(
        fix005($own->field('005')->data())
    ) if (defined($own->field('005')));

    if (defined($bslw_date) && defined($rec_date)) {
        $need_import = DateTime->compare($bslw_date, $rec_date);
    } elsif (defined($rec_date) && !defined($bslw_date)) {
        $need_import = 0;
    }

    return $need_import;
}

1;
