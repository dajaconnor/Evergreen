# ---------------------------------------------------------------
# Copyright © 2012 Merrimack Valley Library Consortium
# Jason Stephenson <jstephenson@mvlc.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the Lesser GNU General Public License as
# published by the Free Software Foundation; either version 3 of the
# License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
# ---------------------------------------------------------------
package JSONPrefs;

use strict;
use warnings;

# A simple perl module to load and save preferences as JSON objects.
BEGIN {
    use Carp;
    use Encode;
    use Exporter;
    use JSON::XS;
    use Scalar::Util qw/blessed/;
    use vars qw/$AUTOLOAD/;
    our ($VERSION);
    $VERSION = '1.1';
}

# Create a new, empty prefs object.
sub new {
    my $class = shift;
    my $self = {};
    $self->{':pretty:'} = shift;
    $self->{':file:'} = undef;
    $self->{':prefs:'} = {};
    bless $self, $class;
    return $self;
}

# Load preferences from a JSON file.  Since we are a blessed hashref,
# we expect the JSON file to contain a JSON object.  If called as a
# class method, creates a new prefs object.  If called as an instance
# method, replaces $self with the loaded data.
sub load {
    my $class_or_self = shift;
    my $file = shift;
    croak("No filename supplied") unless (defined($file));

    my $self = undef;

    my $content;
    if (open(FILE, "<:utf8", "$file")) {
        while (my $line = <FILE>) {
            $content .= $line;
        }
        close(FILE);
    }

    if ($content) {
        if (blessed($class_or_self)) {
            $self = $class_or_self;
        } else {
            $self = $class_or_self->new();
        }
        $self->{':file:'} = $file;
        $self->{':prefs:'} = decode_json($content);
    }

    return $self;
}

# Get or set whether or not we pretty print when saving.
sub pretty {
    my $self = shift;
    if (@_) {
        $self->{':pretty:'} = shift;
    }
    return $self->{':pretty:'};
}

# Write the preference data to a named file.
sub save {
    my $self = shift;
    my $file = shift || $self->{':file:'};
    if ($file && open(FILE, ">:utf8", "$file")) {
        my $pretty = 0;
        # Check if $self->{':pretty:'} is defined && true selon perl.
        $pretty = 1 if (defined($self->{':pretty:'}) && $self->{':pretty:'});
        my $content = JSON::XS->new()->allow_blessed(1)->convert_blessed(1)
            ->pretty($pretty)->encode($self->{':prefs:'});
        print(FILE "$content\n");
        close(FILE);
        $self->{':file:'} = $file;
        return 1;
    } else {
        carp("No file to save to!");
    }
    return 0;
}

# Return an array of the fields in the preferences object.  This does
# not iterate through subobjects at the moment, it only does the first
# level of fields.
sub fields {
    my $self = shift;
    my @fields = ();
    foreach my $key (keys %{$self->{':prefs:'}}) {
        push(@fields, $key);
    }
    return @fields;
}

# Get the value of a field.  You can use this method to get the value
# of a preference field whose name matches another JSONPrefs method.
sub get {
    my $self = shift;
    my $field = shift;
    if (ref($self->{':prefs:'}->{$field}) eq 'HASH'
            && !blessed($self->{':prefs:'}->{$field})) {
        my $temp->{':prefs:'} = $self->{':prefs:'}->{$field};
        bless($temp, blessed($self));
        $self->{':prefs:'}->{$field} = $temp;
    }
    return $self->{':prefs:'}->{$field};
}

# Set the value of a field.  You can use this method to set the value
# of a preference field whose name matches another JSONPrefs method.
sub set {
    my $self = shift;
    my $field = shift;
    return $self->{':prefs:'}->{$field} = shift;
}

# Use field names like methods.  Also blesses any hashref members to
# return them as JSONPrefs objects.
sub AUTOLOAD {
    my $self = shift;
    my $type = ref ($self) || croak "$self is not an object";
    my $field = $AUTOLOAD;
    $field =~ s/.*://;
    if (@_) {
        return $self->set($field, @_);
    } else {
        return $self->get($field);
    }
}

# Used by JSON::XS to convert blessed JSONPrefs back into hashrefs.
sub TO_JSON {
    my $self = shift;
    return {%{$self->{':prefs:'}}};
}

1;
