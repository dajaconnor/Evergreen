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
package Backstage::Email;

use Module::Load;
use MIME::Lite;
use Carp;

sub new {
    my $class = shift;
    $prefs = shift;
    my $self->{'smtp_module'} = 'Net::SMTP';
    my $encryption = $prefs->email->smtp->encryption;
    $self->{'smtp_module'} .= "::SSL" if ($encryption =~ /^ssl$/i);
    $self->{'smtp_module'} .= "::TLS" if ($encryption =~ /^tls$/i);
    $self->{'smtp_host'} = $prefs->email->smtp->host;
    $self->{'smtp_port'} = $prefs->email->smtp->port;
    $self->{'smtp_user'} = $prefs->email->smtp->user;
    $self->{'smtp_password'} = $prefs->email->smtp->password;
    $self->{'smtp_from'} = $prefs->email->smtp->from;
    $self->{'subject'} = undef;
    $self->{'parts'} = [];
    $self->{'recipients'} = [];
    bless($self, $class);
    return $self;
}

sub add_recipient {
    my $self = shift;
    foreach my $recipient (@_) {
        push(@{$self->{'recipients'}}, $recipient);
    }
    return $self->{'recipients'};
}

sub add_part {
    my $self = shift;
    my $part = shift;
    push(@{$self->{'parts'}}, $part);
    return $self->{'parts'};
}

sub subject {
    my $self = shift;
    if (@_) {
        return $self->{'subject'} = shift;
    } else {
        return $self->{'subject'};
    }
}

sub send {
    my $self = shift;

    load $self->{'smtp_module'};

    croak("Email has no subject")  unless ($self->{'subject'});
    croak("Email has no parts") unless (scalar @{$self->{'parts'}});
    croak("Email has no recipients") unless (scalar @{$self->{'recipients'}});

    my $emailFrom = $self->{'smtp_from'}->email;
    $emailFrom = $self->{'smtp_from'}->name . ' <' . $emailFrom . '>'
        if ($self->{'smtp_from'}->name);

    # Create the smtp object.
    my $smtp = $self->{'smtp_module'}->new(
        $self->{'smtp_host'},
        Port => $self->{'smtp_port'},
        User => $self->{'smtp_user'},
        Password => $self->{'smtp_password'}
    );

    # Create the message:
    my $message = MIME::Lite->new(
        From => $emailFrom,
        To => join(',', @{$self->{'recipients'}}),
        Subject => $self->{'subject'},
        Type => 'multipart/mixed'
    );

    # Add the parts.
    foreach my $part (@{$self->{'parts'}}) {
        $message->attach(%{$part});
    }

    $smtp->mail($self->{'smtp_from'}->email);
    $smtp->to(@{$self->{'recipients'}});
    $smtp->data;
    $smtp->datasend($message->as_string);
    $smtp->dataend;
    $smtp->quit;
}

1;
