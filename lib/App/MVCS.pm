package App::MVCS;

# ABSTRACT: Automate version control with Mirth Connect

use Moose;
use namespace::autoclean;

extends 'App::MVCS::Base';

use Class::Load qw( load_class );

=head1 SYNOPSIS

    use App::MVCS;

    my $mvcs = App::MVCS->new;

    $mvcs->run('commit_code');

=head1 DESCRIPTION

This class is used to delegate to supported commands.  See
L<App::MVCS::Base> for a list of supported commands.

The commands are repesented in the C<App::MVCS::Command::*> namespace.

=head1 METHODS

=head2 run

    $mvcs->run('commit_code');

Given a command name, simply calls the C<run> method of the appropriate
class.

=cut

sub run {
    my ( $self, $command, @args ) = @_;

    $command = $self->get_command($command);

    $command->run(@args);
}

=head2 get_command

    $command = $mvcs->get_command('commit_code');

Given a command name, returns an object of the appropriate class.

=cut

sub get_command {
    my ( $self, $command ) = @_;

    my $class = join '::', __PACKAGE__, 'Command', $command;

    load_class($class);

    return $class->new;
}

=head1 ACKNOWLEDGEMENTS

Thanks to the Informatics Corporation of America (ICA) for sponsoring the
development of this module.

=cut

__PACKAGE__->meta->make_immutable;

1;
