#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

my $command_name = "commit_code";
my $class        = "App::Mflow::Command::${command_name}";

use_ok($class);

my $command = $class->new;
$command->run();

done_testing;
