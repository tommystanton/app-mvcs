package App::Mflow;

# ABSTRACT: Facilitate workflow in using Mirth Connect

use Moose;
use namespace::autoclean;

extends 'App::Mflow::Base';

use Class::Load qw( load_class );

sub run {
    my ( $self, $command, @args ) = @_;

    $command = $self->get_command($command);

    $command->run(@args);
}

sub get_command {
    my ( $self, $command ) = @_;

    my $class = join '::', __PACKAGE__, 'Command', $command;

    load_class($class);

    return $class->new;
}

__PACKAGE__->meta->make_immutable;

1;
