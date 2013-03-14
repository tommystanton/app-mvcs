package App::Mflow::TUI;
use Moose;
use namespace::autoclean;

extends 'App::Mflow::Base';

use Term::Clui;

use App::Mflow::Util -svn;

sub run {
    my ($self) = @_;

    my $choice = $self->choose_command();

    # TODO Put in attribute?
    my $mflow = App::Mflow->new;

    if ( $choice eq 'commit_code' ) {
        my $command = $mflow->get_command($choice);

        _prompt_through_commit_code($command);
    }
    else {
        $mflow->run($choice);
    }
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

sub _prompt_through_commit_code {
    my ($command) = @_;

    $command->checkout_repo;
    $command->export_mirth_channels;
    $command->stage_repo;

    my $diff = svn_diff( { path => $command->code_checkout_path } );

    if ($diff) {
        view( 'Diff', $diff );

        if ( confirm('Does the diff look correct?') ) {
            $command->commit_changes_in_repo({
                commit_msg => ask('Enter a commit message:')
            });
        }
        else {
            inform('Aborting.');
        }
    }
    else {
        inform('There were no differences.  There is nothing to do.');
    }
}

__PACKAGE__->meta->make_immutable;

1;
