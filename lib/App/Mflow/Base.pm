package App::Mflow::Base;
use Moose;
use namespace::autoclean;

use MooseX::Types::Tied::Hash::IxHash ':all';

use Path::Class ();
use Config::ZOMG ();

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

        # TODO Consolidate into "Make a tag," then prompt again for
        # which environment
        'Make a Staging tag'    => 'make_staging_tag',
        'Make a UAT tag'        => 'make_uat_tag',
        'Make a Production tag' => 'make_prod_tag',
    ];

    return $commands;
}

__PACKAGE__->meta->make_immutable;

1;
