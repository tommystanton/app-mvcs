#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Differences;

my $class = 'App::Mflow::TUI';

use_ok($class);

my $commands = $class->new->base_commands;

eq_or_diff(
    [ keys %$commands ], # (Verifying that IxHash is working)
    [ 'Commit Mirth code',
      'Make a Staging tag',
      'Make a UAT tag',
      'Make a Production tag',
    ],
    'Order of command options is correct'
);

done_testing;
