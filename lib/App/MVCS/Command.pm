package App::MVCS::Command;

# ABSTRACT: Provide a base class for commands

use Moose;
use namespace::autoclean;

extends 'App::MVCS::Base';

__PACKAGE__->meta->make_immutable;

1;
