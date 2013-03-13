package App::Mflow;
use Moose;
use namespace::autoclean;

extends 'App::Mflow::Base';

use Class::Load qw( load_class );

sub run {
    my ( $self, $command, @args ) = @_;

    $command = $self->_build_command($command);

    $command->run(@args);
}

sub _build_command {
    my ( $self, $command ) = @_;

    my $class = join '::', __PACKAGE__, 'Command', $command;

    load_class($class);

    return $class->new;
}

__PACKAGE__->meta->make_immutable;

1;
