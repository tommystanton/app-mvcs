#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::File;

use Test::Fake::HTTPD 0.06 ();
use Class::Monkey qw( Test::Fake::HTTPD );

use HTTP::Request::Params ();
use Path::Class ();
use File::Temp ();
use YAML::Syck qw( Dump );

my $t_lib_dir = Path::Class::Dir->new('t/lib/mock_mirth/');

_monkey_patch_httpd();
my $httpd = _get_httpd();

ok( defined $httpd, 'Got a test HTTP server (HTTPS)' );

my $config_file = File::Temp->new(
    DIR      => $t_lib_dir->stringify,
    TEMPLATE => 'mflow_test-XXXX',
    SUFFIX   => '.yaml',
);

_generate_test_config_yaml_file({
    httpd => $httpd,
    file  => $config_file->filename,
});

$ENV{MFLOW_CONFIG} = $config_file->filename;

my $command_name = "commit_code";
my $class        = "App::Mflow::Command::${command_name}";

use_ok($class);

my $command = $class->new;
$command->run();

my $export_dir = $command->code_checkout_path;

file_exists_ok(
    "${export_dir}/global_scripts.xml",
    "Global scripts have been exported"
);

file_exists_ok(
    "${export_dir}/code_templates.xml",
    "Code templates have been exported"
);

foreach my $channel ( qw( foobar quux ) ) {
    file_exists_ok(
        "${export_dir}/${channel}.xml",
        "$channel channel has been exported"
    );
}

done_testing;

sub _generate_test_config_yaml_file {
    my ($args) = @_;
    my $httpd = $args->{httpd};
    my $file  = $args->{file};

    my ( $server, $port ) = split /:/, $httpd->host_port;

    my $test_config = {
        mirth => {
            server   => $server,
            port     => $port,
            username => 'admin',
            password => 'admin',
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
            my $quux_xml   = _get_channel_fixture('quux');

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
