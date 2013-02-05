package App::Mflow::Command::commit_code;
use Moose;
use namespace::autoclean;

extends 'App::Mflow::Command';

# ABSTRACT: Export channels from a Mirth Connect box, commit to repository

use MooseX::Types::Path::Class::MoreCoercions qw( AbsDir );

use WebService::Mirth ();
use File::Temp ();
use File::chdir;
use Log::Minimal qw( infof );

use App::Mflow::Util -svn;

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

    $self->checkout_repo;
    $self->export_mirth_channels;
    $self->stage_repo;

    #$self->view_diff;
    $self->commit_changes_in_repo;

    return $self;
}

sub checkout_repo {
    my ($self) = @_;

    svn_checkout({
        url     => $self->config->{repository}->{url},
        to_path => $self->code_checkout_path,
    });
}

sub export_mirth_channels {
    my ($self) = @_;

    $self->_mirth->login;

    $self->_export_global_code;
    $self->_export_channel_code;

    $self->_mirth->logout;

    #infof( 'Mirth channel files are in %s', $self->code_checkout_path );
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

sub stage_repo {
    my ($self) = @_;

#    $self->_mirth->login;
#    my $channel_list = $self->_mirth->channel_list;
#    $self->_mirth->logout;
#
#    #$self->_check_for_renamed_channels($channel_list);
#
#    my @channel_names = keys %$channel_list;
#    my @channel_filenames = map {"${_}.xml"}
#        ( @channel_names, 'global_scripts', 'code_templates' );

    my $statuses = svn_status({ path => $self->code_checkout_path });

    foreach my $filename ( keys %$statuses ) {
        if ( $statuses->{$filename} eq 'unversioned' ) {
            local $CWD = $self->code_checkout_path;

            my $file = $self->code_checkout_path->file($filename);
            svn_add({ paths => [ $file->relative ] });
        }
    }
}

sub _check_for_renamed_channels {
    my ($self) = @_;

    # A renamed channel is effectively a file move: the filename
    # changes, but the ID value in the XML file should be the same.
}

sub view_diff {
    my ($self) = @_;

}

sub commit_changes_in_repo {
    my ($self) = @_;

    local $CWD = $self->code_checkout_path;
    svn_commit({ commit_msg => 'TODO Prompt for commit message' });
}

__PACKAGE__->meta->make_immutable;

1;
