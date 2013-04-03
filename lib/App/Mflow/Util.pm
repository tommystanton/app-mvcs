package App::Mflow::Util;
use Moose;

use MooseX::Params::Validate qw( validated_list );
use MooseX::ClassAttribute;
use MooseX::Types::Path::Class::MoreCoercions qw( AbsFile AbsDir Dir );

use SVN::Client ();
use Path::Class ();
use File::Temp ();
use File::chdir;
use IO::CaptureOutput qw( capture_exec );
use Text::Wrap qw( wrap ); $Text::Wrap::columns = 72;

sub svn_functions {
    map { "svn_${_}" } qw(
        checkout status diff
        add      move   remove mkdir
        commit   revert
    );
}

use Sub::Exporter -setup => {
    exports => [ svn_functions ],
    groups  => {
        svn => [ svn_functions ]
    },
};

use Log::Minimal qw( debugf infof warnf croakf );
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

class_has _diff_output_file => (
    is      => 'ro',
    isa     => AbsFile,
    coerce  => 1,
    default => sub { __PACKAGE__->_temp_file_for_diff_output },
    lazy    => 1,
);

class_has _temp_file_for_diff_output => (
    is      => 'ro',
    isa     => 'File::Temp',
    default => sub { File::Temp->new( SUFFIX => '.diff' ) },
    lazy    => 1,
);

class_has _diff_error_file => (
    is      => 'ro',
    isa     => AbsFile,
    coerce  => 1,
    default => sub { __PACKAGE__->_temp_file_for_diff_error },
    lazy    => 1,
);

class_has _temp_file_for_diff_error => (
    is      => 'ro',
    isa     => 'File::Temp',
    default => sub { File::Temp->new( TEMPLATE => 'error-XXXX' ) },
    lazy    => 1,
);

sub svn_checkout {
    my ( $url, $to_path ) = validated_list(
        \@_,
        url     => { isa => 'Str' },
        to_path => { isa => AbsDir, coerce => 1 },
    );

    infof( 'Checking out repository at %s', $to_path );
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

            if ( $status->copied ) {
                # In actuality, this is "addition-with-history,"
                # resulting from an 'svn copy' or from an 'svn move'
                $status_name = 'copied';
            }
            $statuses{$rel_path} = $status_name;
        },
        0, 1, 1, 0
    );

    return \%statuses;
}

sub svn_diff {
    my ($path_to_diff) = validated_list(
        \@_,
        path => { isa => AbsFile, coerce => 1 },
    );

    __PACKAGE__->_svn->diff(
        [],
        $path_to_diff->stringify, 'HEAD',
        $path_to_diff->stringify, 'WORKING',
        1, 0, 0,
        __PACKAGE__->_diff_output_file->stringify,
        __PACKAGE__->_diff_error_file->stringify,
    );

    my ( $diff, $error );
    # Couldn't use something like IO::String because if a filehandle is
    # used, it must in fact be a real filehandle. :-/
    # http://svn.haxx.se/dev/archive-2006-11/0125.shtml
    # http://svn.haxx.se/dev/archive-2006-11/0126.shtml
    # The workaround is to use temporary files, then read them into
    # scalars.
    $diff  = __PACKAGE__->_diff_output_file->slurp;
    $error = __PACKAGE__->_diff_error_file->slurp;

    if ($error) {
        warnf( "svn diff: $error" );
    }

    return $diff;
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

    debugf("wd: $CWD");

    my @cmd = ( 'svn', 'mkdir', '--parents', $path );
    debugf( '$ %s', ( join ' ', @cmd ) );

    my ( $stdout, $stderr, $success, $exit_code ) = capture_exec(@cmd);
    if ( $success ) {
        debugf( 'svn mkdir: %s', ( join ' ', $stdout, $stderr ) );
        return 1;
    }
    else {
        croakf( "svn mkdir: $stderr" );
        return 0;
    }

    return 0;
}

sub svn_add {
    my ( $path ) = validated_list(
        \@_,
        path => { isa => AbsFile, coerce => 1 },
    );

    debugf( 'Staging file for add: %s', $path );
    __PACKAGE__->_svn->add(
        $path->stringify,
        1
    );
}

sub svn_remove {
    my ($paths) = validated_list(
        \@_,
        paths => { isa => 'ArrayRef' },
    );

    __PACKAGE__->_svn->delete(
        @$paths,
        0
    );
}

sub svn_move {
    my ($from, $to) = validated_list(
        \@_,
        from => { isa => AbsFile, coerce => 1 },
        to   => { isa => AbsFile, coerce => 1 },
    );

    __PACKAGE__->_svn->move(
        $from->stringify,
        undef,
        $to->stringify,
        0
    );
}

sub svn_commit {
    my ( $paths, $commit_msg ) = validated_list(
        \@_,
        paths      => {
            isa     => 'ArrayRef', # TODO Somehow use an ArrayRef of
                                   # AbsFile's (with coercion)
            default => ['.'], },   # (Depends on working directory)
        commit_msg => { isa => 'Str' },
    );

    debugf("wd: $CWD");

    # (Manual coercion)
    $paths =
        [ map { Path::Class::File->new($_)->absolute->stringify }
            @$paths ];

    __PACKAGE__->_svn->log_msg(
        # Found this magical syntax at:
        # https://metacpan.org/source/GRICHTER/SVN-Push-0.02/Push.pm#L449
        sub { ${ $_[0] } = $commit_msg }
    );

    my $commit_info = __PACKAGE__->_svn->commit( $paths, 0 );
    if ( not defined $commit_info ) {
        croakf( 'Something went wrong while trying to commit' );
    }

    my $revision = $commit_info->revision;
    infof( 'Committed revision %d.', $revision );
}

sub svn_revert {
    my ( $paths, $commit_msg, $cleanup, $dry_run ) = validated_list(
        \@_,
        paths      => { isa => 'ArrayRef' },
        cleanup    => { isa => 'Bool' },
        #dry_run    => { isa => 'Bool', optional => 1 },
    );

    debugf("wd: $CWD");

    my @cmd = ( 'svn', 'revert', '--recursive', @$paths );
    debugf( '$ %s', ( join ' ', @cmd ) );

    my ( $stdout, $stderr, $success, $exit_code ) = capture_exec(@cmd);
    if ( $success ) {
        debugf( 'svn revert: %s', ( join ' ', $stdout, $stderr ) );

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
