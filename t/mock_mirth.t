#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;

use Test::Fake::HTTPD 0.06 ();
use Class::Monkey qw( Test::Fake::HTTPD );

use Test::SVN::Repo ();

use HTTP::Request::Params ();
use File::chdir;
use Path::Class ();
use File::Temp ();
use YAML::Syck qw( Dump );
use Mojo::DOM ();

use App::Mflow::Util -svn;

# TODO Check if "svn" is in $PATH (via App::Info?) and SKIP if so

my $t_lib_dir = Path::Class::Dir->new('t/lib/mock_mirth/');

our $Disable_foobar_Channel = 0;
our $Rename_quux_Channel = 0;
our $Delete_foobar_Channel = 0;
_monkey_patch_httpd();

my $svn_repo = Test::SVN::Repo->new;

#_setup_repo( { svn_repo => $svn_repo } );

my $config_file = File::Temp->new(
    DIR      => $t_lib_dir->stringify,
    TEMPLATE => 'mflow_test-XXXX',
    SUFFIX   => '.yaml',
);

$ENV{MFLOW_CONFIG} = $config_file->filename;

my $command_name = "commit_code";
my $class        = "App::Mflow::Command::${command_name}";

use_ok($class);

{
    my $httpd = _get_httpd();

    _generate_test_config_yaml_file({
        httpd    => $httpd,
        svn_repo => $svn_repo,
        file     => $config_file->filename,
    });

    my $command = $class->new;

    $command->checkout_repo;

    $command->export_mirth_channels;

    cmp_deeply(
        {   'global_scripts.xml' => 'unversioned',
            'code_templates.xml' => 'unversioned',
            'foobar.xml'         => 'unversioned',
            'quux.xml'           => 'unversioned',
        },
        subhashof(
            svn_status( { path => $command->code_checkout_path } )
        ),
        'Channel files are exported and unversioned to Subversion'
    );

    $command->stage_repo;

    cmp_deeply(
        svn_status( { path => $command->code_checkout_path } ),
        superhashof({
            'global_scripts.xml' => 'added',
            'code_templates.xml' => 'added',
            'foobar.xml'         => 'added',
            'quux.xml'           => 'added',
        }),
        'Channel files are staged for adding to Subversion'
    );

    $command->commit_changes_in_repo({
        commit_msg_coderef => sub {'Initial commit of channels'}
    });

    cmp_deeply(
        svn_status( { path => $command->code_checkout_path } ),
        {   'global_scripts.xml' => 'normal',
            'code_templates.xml' => 'normal',
            'foobar.xml'         => 'normal',
            'quux.xml'           => 'normal',
            '.'                  => 'normal',
        },
        'Channel files have been committed to Subversion'
    );
}

{
    $Disable_foobar_Channel = 1;
    diag('Disabling foobar channel this time...');
    my $httpd = _get_httpd();

    _generate_test_config_yaml_file({
        httpd    => $httpd,
        svn_repo => $svn_repo,
        file     => $config_file->filename,
    });

    my $command = $class->new;

    $command->checkout_repo;
    $command->export_mirth_channels;
    $command->stage_repo;

    cmp_deeply(
        svn_status( { path => $command->code_checkout_path } ),
        superhashof( { 'foobar.xml' => 'modified' } ),
        'foobar channel appears modified to Subversion'
    );

    $command->commit_changes_in_repo({
        commit_msg_coderef => sub {'Disabled foobar'}
    });

    cmp_deeply(
        svn_status( { path => $command->code_checkout_path } ),
        {   'global_scripts.xml' => 'normal',
            'code_templates.xml' => 'normal',
            'foobar.xml'         => 'normal',
            'quux.xml'           => 'normal',
            '.'                  => 'normal',
        },
        'Channel files have been committed to Subversion'
    );
}

{
    $Rename_quux_Channel = 1;
    diag('Renaming the quux channel this time...');
    my $httpd = _get_httpd();

    _generate_test_config_yaml_file({
        httpd    => $httpd,
        svn_repo => $svn_repo,
        file     => $config_file->filename,
    });

    my $command = $class->new;

    $command->checkout_repo;
    $command->export_mirth_channels;
    $command->stage_repo;

    cmp_deeply(
        svn_status( { path => $command->code_checkout_path } ),
        superhashof({
            'foobar.xml' => 'normal',
            'quux.xml'   => 'deleted',
            'baz.xml'    => 'copied',
        }),
        'quux channel appears as moved to baz to Subversion'
    );

    $command->commit_changes_in_repo({
        commit_msg_coderef => sub {'Channel rename: quux --> baz'}
    });

    cmp_deeply(
        svn_status( { path => $command->code_checkout_path } ),
        {   'global_scripts.xml' => 'normal',
            'code_templates.xml' => 'normal',
            'foobar.xml'         => 'normal',
            'baz.xml'            => 'normal',
            '.'                  => 'normal',
        },
        'Channel files have been committed to Subversion'
    );
}

{
    $Delete_foobar_Channel = 1;
    diag('Deleting the quux channel this time...');
    my $httpd = _get_httpd();

    _generate_test_config_yaml_file({
        httpd    => $httpd,
        svn_repo => $svn_repo,
        file     => $config_file->filename,
    });

    my $command = $class->new;

    $command->checkout_repo;
    $command->export_mirth_channels;
    $command->stage_repo;

    cmp_deeply(
        svn_status( { path => $command->code_checkout_path } ),
        superhashof({
            'foobar.xml' => 'deleted',
            'baz.xml'    => 'normal',
        }),
        'foobar channel appears as deleted to baz to Subversion'
    );

    $command->commit_changes_in_repo({
        commit_msg_coderef => sub {'Delete foobar'}
    });

    cmp_deeply(
        svn_status( { path => $command->code_checkout_path } ),
        {   'global_scripts.xml' => 'normal',
            'code_templates.xml' => 'normal',
            'baz.xml'            => 'normal',
            '.'                  => 'normal',
        },
        'Channel files have been committed to Subversion'
    );
}

done_testing;

sub _setup_repo {
    my ($args) = @_;
    my $svn_repo = $args->{svn_repo};

    my $path_to_checkout = File::Temp->newdir(
            $t_lib_dir->subdir('svn_fixture_checkout-XXXX')->stringify
        );
    my $repo_checkout_dir =
        Path::Class::Dir->new( $path_to_checkout->dirname );

    svn_checkout({
        url     => $svn_repo->url,
        to_path => $repo_checkout_dir->stringify,
    });

    my $mirth_channel_fixtures = {
        foobar         => _get_channel_fixture('foobar'),
        quux           => _get_channel_fixture('quux'),
        global_scripts => _get_global_scripts_fixture(),
        code_templates => _get_code_templates_fixture(),
    };

    foreach my $channel ( keys %$mirth_channel_fixtures ) {
        my $file = $repo_checkout_dir->file("${channel}.xml");

        my $content = $mirth_channel_fixtures->{$channel};
        $file->spew($content);
    }

    local $CWD = $repo_checkout_dir->stringify;
    svn_add({
        paths => [qw(
            foobar.xml quux.xml
            global_scripts.xml code_templates.xml
        )]
    });
    svn_commit({ commit_msg => 'Initial commit of Mirth code' });
}

sub _generate_test_config_yaml_file {
    my ($args)   = @_;
    my $svn_repo = $args->{svn_repo};
    my $httpd    = $args->{httpd};
    my $file     = $args->{file};

    my ( $server, $port ) = split /:/, $httpd->host_port;

    my $test_config = {
        mirth => {
            server   => $server,
            port     => $port,
            username => 'admin',
            password => 'admin',
        },
        repository => {
            type => 'svn',
            url  => $svn_repo->url,
        }
    };

    my $yaml = Dump($test_config);

    my $file_to_write = Path::Class::File->new( $file );
    $file_to_write->spew($yaml);
}

sub _monkey_patch_httpd {
    # XXX Monkey patch for HTTPS certs/ location:
    # mostly copy and paste the original method :-/
    override 'run' => sub {
        my $cert_dir = $t_lib_dir->subdir('certs');

        my %certs_args = (
            SSL_key_file  => $cert_dir->file('server-key.pem')->stringify,
            SSL_cert_file => $cert_dir->file('server-cert.pem')->stringify,
        );

        eval <<'!STUFFY!FUNK!';
    my ($self, $app) = @_;
    
    $self->{server} = Test::TCP->new(
        code => sub {
            my $port = shift;
    
            my $d;
            for (1..10) {
                $d = $self->_daemon_class->new(
                    %certs_args, # XXX Monkey patch
                    LocalAddr => '127.0.0.1',
                    LocalPort => $port,
                    Timeout   => $self->{timeout},
                    Proto     => 'tcp',
                    Listen    => $self->{listen},
                    ($self->_is_win32 ? () : (ReuseAddr => 1)),
                ) and last;
                Time::HiRes::sleep(0.1);
            }
    
            croak("Can't accepted on 127.0.0.1:$port") unless $d;
    
            $d->accept; # wait for port check from parent process
    
            while (my $c = $d->accept) {
                while (my $req = $c->get_request) {
                    my $res = $self->_to_http_res($app->($req));
                    $c->send_response($res);
                }
                $c->close;
                undef $c;
            }
        },
        ($self->{port} ? (port => $self->{port}) : ()),
    );
    
    weaken($self);
    $self;
!STUFFY!FUNK!
    }, qw( Test::Fake::HTTPD );
}

# Mock a Mirth Connect server
sub _get_httpd {
    my $httpd = Test::Fake::HTTPD->new( scheme => 'https' );
    $httpd->run( sub {
        my $params = HTTP::Request::Params->new( { req => $_[0] } )->params;

        my $response;
        if ( $params->{op} eq 'login' ) {
            my ( $username, $password )
                = map { $params->{$_} } qw( username password );

            my $is_auth =
                $username eq 'admin' && $password eq 'admin' ? 1 : 0;

            # TODO Return a cookie

            if ($is_auth) {
                $response = [
                    200,
                    [ 'Content-Type' => 'text/plain' ],
                    [ 'true' ]
                ];
            }
            else {
                $response = [ 500, [], [] ];
            }
        }
        elsif ( $params->{op} eq 'getCodeTemplate' ) {
            my $code_templates_xml = _get_code_templates_fixture();

            $response = [
                200,
                [ 'Content-Type' => 'application/xml' ],
                [ $code_templates_xml ]
            ];
        }
        elsif ( $params->{op} eq 'getGlobalScripts' ) {
            my $global_scripts_xml = _get_global_scripts_fixture();

            $response = [
                200,
                [ 'Content-Type' => 'application/xml' ],
                [ $global_scripts_xml ]
            ];
        }
        elsif ( $params->{op} eq 'getChannel' ) {
            my $foobar_xml = _get_channel_fixture('foobar');

            # Hack to disable on-the-fly
            if ($Disable_foobar_Channel) {
                my $dom = Mojo::DOM->new(
                    qq{<?xml version="1.0"?>\n$foobar_xml}
                );
                $dom->at('channel > enabled')
                    ->replace_content('false');

                $foobar_xml = $dom . '';
            }
            if ($Delete_foobar_Channel) {
                $foobar_xml = '';
            }

            my $quux_xml   = _get_channel_fixture('quux');
            if ($Rename_quux_Channel) {
                my $dom = Mojo::DOM->new(
                    qq{<?xml version="1.0"?>\n$quux_xml}
                );
                $dom->at('channel > name')
                    ->replace_content('baz');

                $quux_xml = $dom . '';
            }

            my $channels_xml = <<"END_XML";
<list>
$foobar_xml
$quux_xml
</list>
END_XML

            $response = [
                200,
                [ 'Content-Type' => 'application/xml' ],
                [ $channels_xml ]
            ];
        }
        elsif ( $params->{op} eq 'logout' ) {
            $response = [ 200, [], [] ];
        }

        return $response;
    });

    return $httpd;
}

sub _get_global_scripts_fixture {
    my $global_scripts = $t_lib_dir->file("global_scripts.xml");

    my @lines = $global_scripts->slurp;
    my $global_scripts_xml = join '', @lines;

    return $global_scripts_xml;
}

sub _get_code_templates_fixture {
    my $code_templates = $t_lib_dir->file("code_templates.xml");

    my @lines = $code_templates->slurp;
    my $code_templates_xml = join '', @lines;

    return $code_templates_xml;
}

sub _get_channel_fixture {
    my ($channel_to_get) = @_;

    my $channels_dir = $t_lib_dir->subdir('channels');
    my $channel      = $channels_dir->file("${channel_to_get}.xml");

    my @lines = $channel->slurp;
    my $channel_xml = join '', @lines;

    return $channel_xml;
}
