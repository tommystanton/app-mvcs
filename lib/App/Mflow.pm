package App::Mflow;

# ABSTRACT: Facilitate workflow in using Mirth Connect

=head1 NAME

App::Mflow - Facilitate workflow in using Mirth Connect

=cut

use Moose;
use namespace::autoclean;

extends 'App::Mflow::Base';

use Class::Load qw( load_class );

=head1 SYNOPSIS

    use App::Mflow;

    my $mflow = App::Mflow->new;

    $mflow->run('commit_code');

=head1 DESCRIPTION

This class is used to delegate to supported commands.  See
L<App::Mflow::Base> for a list of supported commands.

The commands are repesented in the C<App::Mflow::Command::*> namespace.

=head1 METHODS

=head2 run

    $mflow->run('commit_code');

Given a command name, simply calls the C<run> method of the appropriate
class.

=cut

sub run {
    my ( $self, $command, @args ) = @_;

    $command = $self->get_command($command);

    $command->run(@args);
}

=head2 get_command

    $command = $mflow->get_command('commit_code');

Given a command name, returns an object of the appropriate class.

=cut

sub get_command {
    my ( $self, $command ) = @_;

    my $class = join '::', __PACKAGE__, 'Command', $command;

    load_class($class);

    return $class->new;
}

__PACKAGE__->meta->make_immutable;

1;
