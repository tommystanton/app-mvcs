package App::Mflow::Base;

=head1 NAME

App::Mflow::Base - Provide a base class for shared configuration of Mflow

=cut

use Moose;
use namespace::autoclean;

use MooseX::Types::Tied::Hash::IxHash ':all';

use Path::Class ();
use Config::ZOMG ();

=head1 ATTRIBUTES

=head2 config

Contains a hashref which is populated using L<Config::ZOMG>.  The config
file to be consumed should be a YAML file that looks like this:

    ---
    mirth:
      server: my-mirth.example.com
      port: 8443
      username: admin
      password: my_password
    svn:
      url: file:///path/to/a/repo

The default path that is checked is in C<config/> in the distribution.
The name of the config file should be C<mflow.yaml>, or can be
overridden with C<mflow_local.yaml>.  Additionally, the path to the
config file can be overridden via the environment variable
C<MFLOW_CONFIG>.

The C<mirth> section of the config is used internally with
L<WebService::Mirth>.

=cut

has config => (
    isa        => 'HashRef',
    is         => 'ro',
    required   => 1,
    lazy_build => 1,
);

sub _build_config {
    my ($self) = @_;

    my $default_filepath =
        Path::Class::File->new( __FILE__ )->dir
                                          ->parent->parent->parent
                                          ->subdir('config')->stringify;

    my $config = Config::ZOMG->new(
        name       => 'mflow',
        path       => $default_filepath,
        env_lookup => 'MFLOW_CONFIG',
    );

    return $config->load;
}

=head2 base_commands

Contains a hashref of supported commands, where the key is a description
(ie. "Commit Mirth Code") and the value is the name of the command (ie.
"commit_code").

This is used by L<App::Mflow::TUI> for the main menu of the text-based
user interface for Mflow.

=cut

has base_commands => (
    is         => 'ro',
    isa        => IxHash,
    coerce     => 1,
    lazy_build => 1,
);

sub _build_base_commands {
    my ($self) = @_;

    my $commands = [
        'Commit Mirth code'    => 'commit_code',

        ## TODO Consolidate into "Make a tag," then prompt again for
        ## which environment
        #'Make a Staging tag'    => 'make_staging_tag',
        #'Make a UAT tag'        => 'make_uat_tag',
        #'Make a Production tag' => 'make_prod_tag',
    ];

    return $commands;
}

__PACKAGE__->meta->make_immutable;

1;
