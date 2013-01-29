package App::Mflow::TUI;
use Moose;
use namespace::autoclean;

extends 'App::Mflow::Base';

use Term::Clui;

sub run {
    my ($self) = @_;

    my $command = $self->choose_command();

    # TODO Put in attribute?
    my $mflow = App::Mflow->new;
    # XXX No extra parameters are yet passed
    $mflow->run($command);
}

sub choose_command {
    my ($self) = @_;

    my $commands = $self->base_commands;
    my $choice = choose( "Which command?", keys %$commands );

    my $command;
    if ( defined $choice ) {
        $command = $commands->{$choice};

        return $command;
    }
    else {
        exit(0);
    }

    return $command;
}

__PACKAGE__->meta->make_immutable;

1;
