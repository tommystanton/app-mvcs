package App::Mflow::Util;
use Moose;

use MooseX::Params::Validate qw( validated_list );
use MooseX::Types::Path::Class::MoreCoercions qw( Dir );

use File::chdir;
use IO::CaptureOutput qw( capture_exec );
use Text::Wrap qw( wrap ); $Text::Wrap::columns = 72;

sub svn_functions {
    map { "svn_${_}" } qw( checkout add mkdir commit revert );
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

sub svn_checkout {
    my ( $url, $to_path, $dry_run ) = validated_list(
        \@_,
        url     => { isa => 'Str' },
        to_path => { isa => Dir, coerce => 1 },
        dry_run => { isa => 'Bool', optional => 1 },
    );

    if ($dry_run) {
        infof( "svn checkout: $url $to_path" );
        return 1;
    }

    infof("wd: $CWD");

    my @cmd = ( 'svn', 'checkout', $url, $to_path );
    infof( '$ %s', ( join ' ', @cmd ) );

    my ( $stdout, $stderr, $success, $exit_code ) = capture_exec(@cmd);
    if ( $success ) {
        infof( 'svn checkout: %s', ( join ' ', $stdout, $stderr ) );
        return 1;
    }
    else {
        croakf( "svn checkout: $stderr" );
        return 0;
    }

    return 0;
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

__PACKAGE__->meta->make_immutable;

1;
