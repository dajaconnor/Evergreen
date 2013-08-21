#!/usr/bin/perl
# Copyright © 2012 Jason J.A. Stephenson <jason@sigio.com>
#
# disbatcher.pl is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# disbatcher.pl is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with disbatcher.pl.  If not, see
# <http://www.gnu.org/licenses/>.

use Getopt::Long;

$SIG{CHLD} = \&sig_handler;

my $num = 2;
my $verbose = 0;
my $sleep = 0;
my $file;

my $result = GetOptions("verbose" => \$verbose,
                        "num=i" => \$num,
                        "file=s" => \$file,
                        "sleep=i" => \$sleep);

my @commands = ();

my ($goal, $count, $running) = (0,0,0);

my $fh = *STDIN;

if ($file) {
    open($fh, "<$file") or die("Cannot open $file");
}

while (<$fh>) {
    chomp;
    if ($_) {
        push(@commands, $_);
        $goal++;
    }
}

close($fh) if ($file);

while ($count < $goal) {
    if (scalar(@commands) && $running < $num) {
        my $command = shift(@commands);
        dispatch($command);
    } else {
        sleep($sleep) if ($sleep);
    }
    print "$count of $goal processed\n" if ($verbose && $count);
    print "$running of $num running\n" if ($verbose && $running);
}

sub dispatch {
    my $command = shift;
    my $pid = fork();
    if (!defined($pid)) {
        die("Cannot reproduce!");
    } elsif ($pid) {
        $running++;
        print("dispatched: $command\n") if ($verbose);
    } elsif ($pid == 0) {
        exec($command);
        die("exec of $command failed");
    }
}

sub sig_handler {
    $running--;
    $count++;
}

__END__

=head1 NAME

disbatcher.pl - Dispatches and batches a list of commands

=head1 SYNOPSIS

C<disbatcher.pl>  [B<--verbose>] [B<--file>=I<filename>] [B<--num>=I<number>]
[B<--sleep>=I<seconds>]

=head1 DESCRIPTION

For a given list of commands stored in a I<file> or passed in via
standard input, B<disbatcher.pl> reads the command list into an array
and then batches them, running I<num> of them simultaneously.  As each
command finishes, the next command is started.  The program will
maintain I<num> commands running until the command list is exhausted.
At which point, it will simply wait until the remaining commands
finish running.

For the sake of efficiency, you can tell the program to I<sleep> once
it has hit I<num> running processes.  This will cause the loop to
temporarily stop iterating until either the sleep expires or one of
the running processes finishes.  Sleeping will improve, not degrade,
performance, since we use signals to determine when to start a new
process.

If you tell the program to be I<verbose>, it will periodically output
the number of running processes, the number of finished processes, and
the command line of each process as it is started.

=head1 EXAMPLES

Not today, maybe later.

=head1 BUGS

This is some simple, yet powerful, code.  It makes a very nice footgun
if you are not paying attention with your options.  You can easily
fork bomb your system if you set the value of the I<num> argument too
high.  You are expected to know what you are doing, and if you don't,
then don't use this software until you do know.

=head1 AUTHOR

Jason Stephenson <jason@sigio.com>

=head1 COPYRIGHT AND LICENSE

Copyright © 2012 Jason J.A. Stephenson <jason@sigio.com>

disbatcher.pl is free software: you can redistribute it and/or
modify it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

disbatcher.pl is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.


=cut


