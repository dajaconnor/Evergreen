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
package Backstage::FTP;

use strict;
use warnings;

use Net::FTP;
use File::Basename;
use Carp;

sub new {
    my $class = shift;
    my $prefs = shift;
    my $self->{'prefs'} = $prefs->ftp;
    $self->{'signed_on'} = 0;
    bless($self, $class);
    return $self;
}

sub sign_on {
    my $self = shift;
    $self->{'ftp'} = Net::FTP->new($self->{'prefs'}->host,
                                   Passive => $self->{'prefs'}->passive)
        or croak("Failed to connect to " . $self->{'prefs'}->host);
    $self->{'ftp'}->login($self->{'prefs'}->username,$self->{'prefs'}->password)
        or croak($self->{'ftp'}->message);
    $self->{'ftp'}->binary or croak $self->{'ftp'}->message;
    $self->{'signed_on'} = 1;
}

sub sign_off {
    my $self = shift;
    if ($self->{'signed_on'}) {
        $self->{'ftp'}->quit();
        $self->{'signed_on'} = 0;
    }
}

sub upload {
    my $self = shift;
    my $file = shift;
    my @stat = stat($file);

    if (scalar @stat) {
        $self->sign_on unless ($self->{'signed_on'});
        $self->{'ftp'}->cwd($self->{'prefs'}->upload_dir)
            or croak $self->{'ftp'}->message;
        $self->{'ftp'}->put($file, basename($file))
            or croak $self->{'ftp'}->message;
        $self->sign_off;
        return basename($file);
    } else {
        croak("$file does not exist");
    }

    return undef;
}

sub download {
    my $self = shift;
    my @filenames = ();
    my $source = $self->{'prefs'}->download->source_dir;
    my $destination = $self->{'prefs'}->download->destination_dir;

    $self->sign_on unless ($self->{'signed_on'});
    $self->{'ftp'}->cwd($source) or croak $self->{'ftp'}->message;
    my @remotes = $self->{'ftp'}->dir;
    foreach my $remote (@remotes) {
        my @parts = split(/ +/, $remote);
        my $file = $parts[$#parts];
        my $target = $destination . "/" . $file;
        if ($self->{'ftp'}->get($file, $target)) {
            push(@filenames, $target);
            if ($self->{'prefs'}->download->delete_files) {
                carp $self->{'ftp'}->message
                    unless ($self->{'ftp'}->delete($file));
            }
        } else {
            carp $self->{'ftp'}->message;
        }
    }
    $self->sign_off;

    return @filenames;
}

1;
