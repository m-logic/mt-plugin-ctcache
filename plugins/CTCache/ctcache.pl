package MT::Plugin::CTCache;

use strict;
use MT;
use MT::Plugin;

@MT::Plugin::CTCache::ISA = qw(MT::Plugin);

my $PLUGIN_NAME = 'CTCache';
my $VERSION = '0.1';
my $plugin = new MT::Plugin::CTCache({
    name => $PLUGIN_NAME,
    version => $VERSION,
    description => 'This plugin caches some internal data of Content Type that is repeated referrenced.',
    author_name => 'M-Logic, Inc.',
    author_link => 'http://m-logic.co.jp/',

});

use MT::ContentType;

my $saved_all_permissions;
my $clear_all_permissions;

if (MT->version_number >= 7) { # required MT7
    unless($saved_all_permissions) {
        require MT::ContentType;
        no warnings 'once';
        no warnings 'redefine';
        $saved_all_permissions = \&MT::ContentType::all_permissions;
        *MT::ContentType::all_permissions = \&new_all_permissions;
    }
    MT->add_plugin($plugin);
    if ($MT::DebugMode) {
        require MT::Util::Log;
        require Data::Dumper;
        MT::Util::Log->init();
    }
}

sub instance { $plugin; }

sub new_all_permissions {
    my $class = shift;

    my $driver = $class->driver;
    return {} unless $driver && $driver->table_exists($class);

    if (exists $driver->{ct_permissions} && ref($driver->{ct_permissions}) eq 'HASH' && !$clear_all_permissions) {
        MT::Util::Log->info('[new_all_permissions]:return cache') if $MT::DebugMode;
        return $driver->{ct_permissions};
    }
    MT::Util::Log->info('[new_all_permissions]:no cache') if $MT::DebugMode;

    require MT::ContentType;
    my @all_permissions;
    my @content_types
        = MT::ContentType::_eval_if_mssql_server_or_oracle( sub { @{ $class->load_all } } );
    for my $content_type (@content_types) {
        push( @all_permissions, $content_type->permissions )
            if $content_type->blog;
    }
    my %all_permission = map { %{$_} } @all_permissions;
    #foreach my $k (keys %all_permission) {
    #    my $p = $all_permission{$k};
    #    next unless exists $p->{inherit_from} && ref($p->{inherit_from}) eq 'ARRAY';
    #    $all_permission{$k}->{inherit_from} = [ sort {$a cmp $b} @{$all_permission{$k}->{inherit_from}} ];
    #}
    $driver->{ct_permissions} = \%all_permission;
    $clear_all_permissions = 0;
    return \%all_permission;
}

1;
