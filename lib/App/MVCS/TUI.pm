package App::MVCS::TUI;
use Moose;
use namespace::autoclean;

extends 'App::MVCS::Base';

use Term::Clui;

use App::MVCS::Util -svn;

sub run {
    my ($self) = @_;

    $self->show_welcome();
    my $choice = $self->choose_command();

    # TODO Put in attribute?
    my $mvcs = App::MVCS->new;

    if ( $choice eq 'commit_code' ) {
        my $command = $mvcs->get_command($choice);

        _prompt_through_commit_code($command);
    }
    else {
        $mvcs->run($choice);
    }
}

sub show_welcome {
    my ($self) = @_;

    print <<EOT;
Welcome to MVCS: Mirth Version Control System
EOT
}

sub choose_command {
    my ($self) = @_;

    my $commands = $self->base_commands;

    print <<EOT;
  Use the arrow keys (or hjkl) to move the cursor over a selection, then
  press enter to choose it.  Quit with q.
EOT
    my $choice = choose( 'Choose a command:', keys %$commands );

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
