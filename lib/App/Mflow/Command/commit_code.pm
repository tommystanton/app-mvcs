package App::Mflow::Command::commit_code;
use Moose;
use namespace::autoclean;

extends 'App::Mflow::Command';

# ABSTRACT: Export channels from a Mirth Connect box, commit to repository

use MooseX::Params::Validate qw( validated_list );
use MooseX::Types::Path::Class::MoreCoercions qw( File AbsDir );

use WebService::Mirth ();
use File::Temp ();
use Path::Class ();
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

    $self->_check_for_renamed_channels;

    my $statuses = svn_status({ path => $self->code_checkout_path });

    foreach my $filename ( keys %$statuses ) {
        if ( $statuses->{$filename} eq 'unversioned' ) {
            local $CWD = $self->code_checkout_path;

            my $file = $self->code_checkout_path->file($filename);
            svn_add({ paths => [ $file->relative ] });
        }
    }
}

# A renamed channel is effectively a file move: the filename changes,
# but the ID value in the XML file should be the same.
sub _check_for_renamed_channels {
    my ($self) = @_;

    my $channels_to_move = $self->_get_list_of_renamed_channels;

    for (@$channels_to_move) {
        local $CWD = $self->code_checkout_path;
        $self->_do_move_for_channel_rename({
            from => $_->{from} . '.xml',
            to   => $_->{to}   . '.xml',
        });
    }
}

sub _do_move_for_channel_rename {
    my $self = shift;
    my ($from, $to) = validated_list(
        \@_,
        from => { isa => File, coerce => 1 },
        to   => { isa => File, coerce => 1 },
    );

    my $unstaged_move_content = sub {
        my $content = $to->slurp;
        unlink $to->stringify;

        return $content;
    }->();

    svn_move( { from => $from, to => $to } );

    if ($unstaged_move_content) {
        # Overwrite with the newest content, preserving the working copy
        # status from 'svn move'
        $to->spew($unstaged_move_content);
    }
}

sub _get_list_of_renamed_channels {
    my ($self) = @_;

    my %local  = %{ $self->_get_local_channel_list };
    my %remote = %{ $self->_get_remote_channel_list };

    # Based on hash comparison idea from Shlomi Fish:
    # http://www.nntp.perl.org/group/perl.beginners/2012/03/msg120335.html
    my %merged = ( %local, %remote );

    my $channel_renames = [];
    foreach my $name ( keys %merged ) {
        my ( $old, $new );

        if ( exists $local{$name} and not exists $remote{$name} ) {
            $old->{name} = $name;
            $old->{id}   = $local{$name};

            foreach my $remote_name ( keys %remote ) {
                if ( $remote{$remote_name} eq $old->{id} ) {
                    $new->{name} = $remote_name;
                    $new->{id}   = $remote{$remote_name};

                    last;
                }
            }
        }
        else {
            next;
        }

        push @$channel_renames, {
            from => $old->{name},
            to   => $new->{name},
        };
    }

    return $channel_renames;
}

sub _get_local_channel_list {
    my ($self) = @_;

    my $statuses = svn_status( { path => $self->code_checkout_path } );

    my @channel_xml_files =
        grep { $_ =~ /\.xml$/ &&
               $_ !~ /(?:code_templates|global_scripts)/ }
            keys %$statuses;

    my %channel_list;
    foreach my $file (@channel_xml_files) {
        local $CWD = $self->code_checkout_path;
        my $xml = Path::Class::File->new($file)->slurp;
        my $dom = Mojo::DOM->new($xml);

        my $channel =
            WebService::Mirth::Channel->new( { channel_dom => $dom } );

        my $name = $channel->name;
        my $id   = $channel->id;

        # TODO Store filename in this data structure as well?
        $channel_list{$name} = $id;
    }

    return \%channel_list;
}

sub _get_remote_channel_list {
    my ($self) = @_;

    $self->_mirth->login;
    my $channel_list = $self->_mirth->channel_list;
    $self->_mirth->logout;

    return $channel_list;
}

sub view_diff {
    my ($self) = @_;

}

sub commit_changes_in_repo {
    my $self = shift;
    my ($commit_msg_coderef) = validated_list(
        \@_,
        commit_msg_coderef => {
            isa     => 'CodeRef',
            default => sub {'Committing channels'},
        },
    );

    my $commit_msg = $commit_msg_coderef->();

    local $CWD = $self->code_checkout_path;
    svn_commit({ commit_msg => $commit_msg });
}

__PACKAGE__->meta->make_immutable;

1;
