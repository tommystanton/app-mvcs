package App::Mflow::Util;
use Moose;

use MooseX::Params::Validate qw( validated_list );
use MooseX::ClassAttribute;
use MooseX::Types::Path::Class::MoreCoercions qw( AbsDir Dir );

use SVN::Client ();
use Path::Class ();
use File::chdir;
use IO::CaptureOutput qw( capture_exec );
use Text::Wrap qw( wrap ); $Text::Wrap::columns = 72;

sub svn_functions {
    map { "svn_${_}" } qw( checkout status add mkdir commit revert );
}

use Sub::Exporter -setup => {
    exports => [ svn_functions ],
    groups  => {
        svn => [ svn_functions ]
    },
};

use Log::Minimal qw( infof warnf croakf );
$Log::Minimal::PRINT = sub {
    my ( $time, $type, $message, $trace, $raw_message ) = @_;
    print "$type: $message\n";
};

class_has _svn => (
    is      => 'ro',
    isa     => 'SVN::Client',
    default => sub { SVN::Client->new },
    lazy    => 1,
);

class_has _svn_statuses => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
);

sub _build__svn_statuses {
    my ($self) = @_;

    # These are listed in the CONSTANTS section of the documentation for
    # SVN::Wc
    my @status_names = qw(
        added conflicted deleted external ignored incomplete
        merged missing modified none normal obstructed
        replaced unversioned
    );

    my %statuses;
    foreach my $status_name (@status_names) {
        my $status_code;
        {
            no strict 'refs';
            $status_code = ${"SVN::Wc::Status::${status_name}"};
        }

        $statuses{$status_code} = $status_name;
    }

    return \%statuses;
}

sub svn_checkout {
    my ( $url, $to_path ) = validated_list(
        \@_,
        url     => { isa => 'Str' },
        to_path => { isa => AbsDir, coerce => 1 },
    );

    infof( 'Checking out repoistory at %s', $to_path );
    __PACKAGE__->_svn->checkout(
        $url,
        $to_path->stringify,
        'HEAD',
        0,
    );
}

sub svn_status {
    my ($abs_path) = validated_list(
        \@_,
        path => { isa => AbsDir, coerce => 1 },
    );

    my %statuses;
    __PACKAGE__->_svn->status(
        $abs_path->stringify,
        'HEAD',
        sub {
            my ( $svn_path, $status ) = @_;

            my $status_code = $status->text_status;
            my $status_name = __PACKAGE__->_svn_statuses->{$status_code};

            my $rel_path = Path::Class::File->new($svn_path)
                                            ->relative($abs_path);

            $statuses{$rel_path} = $status_name;
        },
        0, 1, 1, 0
    );

    return \%statuses;
}

sub svn_mkdir {
    my ( $path, $dry_run ) = validated_list(
        \@_,
        path    => { isa => Dir, coerce => 1 },
        dry_run => { isa => 'Bool', optional => 1 },
    );

    if ($dry_run) {
        infof( "svn mkdir: $path" );
        return 1;
    }

    infof("wd: $CWD");

    my @cmd = ( 'svn', 'mkdir', '--parents', $path );
    infof( '$ %s', ( join ' ', @cmd ) );

    my ( $stdout, $stderr, $success, $exit_code ) = capture_exec(@cmd);
    if ( $success ) {
        infof( 'svn mkdir: %s', ( join ' ', $stdout, $stderr ) );
        return 1;
    }
    else {
        croakf( "svn mkdir: $stderr" );
        return 0;
    }

    return 0;
}

sub svn_add {
    my ( $paths ) = validated_list(
        \@_,
        paths => { isa => 'ArrayRef' },
    );

    infof("wd: $CWD");

    my @cmd = ( 'svn', 'add', @$paths );
    infof( '$ %s', ( join ' ', @cmd ) );

    my ( $stdout, $stderr, $success, $exit_code ) = capture_exec(@cmd);
    if ( $success ) {
        infof( 'svn add: %s', ( join ' ', $stdout, $stderr ) );
        return 1;
    }
    else {
        croakf( "svn add: $stderr" );
        return 0;
    }

    return 0;
}

sub svn_commit {
    my ( $paths, $commit_msg, $dry_run ) = validated_list(
        \@_,
        paths      => { isa => 'ArrayRef', optional => 1, default => [], },
        commit_msg => { isa => 'Str' },
        dry_run    => { isa => 'Bool', optional => 1 },
    );

    if ($dry_run) {
        infof( "svn commit: %s", ( join " ", @$paths ) );
        return 1;
    }

    infof("wd: $CWD");

    my @cmd = ( 'svn', 'commit', '-m', $commit_msg, @$paths );
    infof( '$ %s', ( join ' ', @cmd[0..1], @cmd[4..$#cmd] ) );

    my ( $stdout, $stderr, $success, $exit_code ) = capture_exec(@cmd);
    if ( $success ) {
        infof( 'svn commit: %s', ( join ' ', $stdout, $stderr ) );
        return 1;
    }
    else {
        croakf( "svn commit: $stderr" );
        return 0;
    }

    return 0;
}

sub svn_revert {
    my ( $paths, $commit_msg, $cleanup, $dry_run ) = validated_list(
        \@_,
        paths      => { isa => 'ArrayRef' },
        cleanup    => { isa => 'Bool' },
        #dry_run    => { isa => 'Bool', optional => 1 },
    );

    infof("wd: $CWD");

    my @cmd = ( 'svn', 'revert', '--recursive', @$paths );
    infof( '$ %s', ( join ' ', @cmd ) );

    my ( $stdout, $stderr, $success, $exit_code ) = capture_exec(@cmd);
    if ( $success ) {
        infof( 'svn revert: %s', ( join ' ', $stdout, $stderr ) );

        if ($cleanup) {
            # TODO Remove unknown files
        }

        return 1;
    }
    else {
        warnf( "svn revert: $stderr" );

        my $notice = <<EOT;
The working copy was left dirty.  Run 'svn status' in the repository
check-out to investigate what was left over.
EOT
        print wrap( q{}, q{},
            join( q{ }, split /\n/, $notice )
        );

        return 0;
    }

    return 0;
}

no Moose;
no MooseX::ClassAttribute;

__PACKAGE__->meta->make_immutable;

1;
