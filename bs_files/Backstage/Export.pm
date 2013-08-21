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
package Backstage::Export;

use strict;
use warnings;

use MARC::Record;
use MARC::File::XML;
use MARC::File::USMARC;
use Encode;
use OpenSRF::AppSession;
use OpenSRF::System;
use POSIX qw/strftime/;

sub new {
    my $class = shift;
    my $self->{'prefs'} = shift;
    bless $self, $class;
    return $self;
}

sub run {
    my $self = shift;

    my $prefs = $self->{'prefs'};
    OpenSRF::System->bootstrap_client(config_file=>
                                          $prefs->evergreen->osrf_config);
    my $now = OpenSRF::AppSession->create('opensrf.settings')
        ->request('opensrf.system.time')->gather(1);

    my $query = {
        'select' => {'bre' => ['id', 'source', 'marc']},
        'from' => 'bre',
        'where' => {
            'id' => {'>' => -1},
            'deleted' => 'f',
            'create_date' => {'>' => $prefs->export->last_run_date},
            '-or' => [{'source' => undef}, {'source' =>
                                                $prefs->export->sources }]
        }
    };

    if (open(OUTPUT, '>:utf8', $prefs->export->output)) {
        my $request = OpenSRF::AppSession->create('open-ils.cstore')
            ->request('open-ils.cstore.json_query', $query);
        while (my $response = $request->recv) {
            my $result = $response->content;
            my $record = MARC::Record->new_from_xml($result->{marc}, 'UTF-8');
            print(OUTPUT $record->as_usmarc);
        }
        $request->finish();
        close(OUTPUT);
        $prefs->export->last_run_date(strftime("%F %T%z", localtime($now)));
        $prefs->pretty(1); #pretty print prefs for easier hand editing.
        $prefs->save;
        return $prefs->export->output;
    }

    return undef;
}

1;
