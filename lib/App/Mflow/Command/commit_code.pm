package App::Mflow::Command::commit_code;
use Moose;
use namespace::autoclean;

extends 'App::Mflow::Command';

# ABSTRACT: Export channels from a Mirth Connect box, commit to repository

use MooseX::Types::Path::Class::MoreCoercions qw( AbsDir );

use WebService::Mirth ();
use File::Temp ();
use Log::Minimal qw( infof );

has code_checkout_path => (
    is      => 'ro',
    isa     => AbsDir,
    coerce  => 1,
    default => sub { $_[0]->_temp_dir_for_checkout },
    lazy    => 1,
);

has _temp_dir_for_checkout => (
    is      => 'ro',
    isa     => 'File::Temp::Dir',
    default => sub { File::Temp->newdir },
    lazy    => 1,
);

has _mirth => (
    is      => 'ro',
    isa     => 'WebService::Mirth',
    default => sub { WebService::Mirth->new( $_[0]->config->{mirth} ) },
    lazy    => 1,
);

sub run {
    my ($self) = @_;

    $self->export_mirth_channels;

    #$self->stage_changes_in_repo;

    #$self->revert_changes_in_repo;

    #$self->view_diff;
    #$self->commit_changes_in_repo;

    return $self;
}

sub export_mirth_channels {
    my ($self) = @_;

    $self->_mirth->login;

    $self->_export_global_code;
    $self->_export_channel_code;

    $self->_mirth->logout;

    infof( 'Mirth channel files are in %s', $self->code_checkout_path );
}

sub _export_global_code {
    my ($self) = @_;

    $self->_mirth->export_global_scripts({
        to_dir => $self->code_checkout_path
    });

    $self->_mirth->export_code_templates({
        to_dir => $self->code_checkout_path
    });
}

sub _export_channel_code {
    my ($self) = @_;

    $self->_mirth->export_channels({
        to_dir => $self->code_checkout_path
    });
}

sub stage_changes_in_repo {
    my ($self) = @_;

    #$self->_check_for_renamed_channels;
}

sub _check_for_renamed_channels {
    my ($self) = @_;

    # A renamed channel is effectively a file move: the filename
    # changes, but the ID value in the XML file should be the same.
}

sub revert_changes_in_repo {
    my ($self) = @_;

}

sub view_diff {
    my ($self) = @_;

}

sub commit_changes_in_repo {
    my ($self) = @_;

}

__PACKAGE__->meta->make_immutable;

1;
