package MT::Plugin::CTCache;

use strict;
use MT;
use MT::Plugin;

@MT::Plugin::CTCache::ISA = qw(MT::Plugin);

my $PLUGIN_NAME = 'CTCache';
my $VERSION = '0.3';
my $plugin = new MT::Plugin::CTCache({
    name => $PLUGIN_NAME,
    version => $VERSION,
    description => 'This plugin caches some internal data of Movable Type that is repeated referrenced.',
    author_name => 'M-Logic, Inc.',
    author_link => 'http://m-logic.co.jp/',
    registry => {
        callbacks => {
            'template_param.edit_role' => {
                handler  => \&hdlr_tmpl_param_edit_role,
                priority => 10,
            },
        },
    },
});

use MT::ContentType;
use MT::Permission;

my $saved_permission_to_hash;
my $saved_all_permissions;

if (MT->version_number >= 7) { # required MT7
    unless($saved_all_permissions) {
        require MT::ContentType;
        no warnings 'once';
        no warnings 'redefine';
        $saved_all_permissions = \&MT::ContentType::all_permissions;
        *MT::ContentType::all_permissions = \&new_all_permissions;
    }
    unless($saved_permission_to_hash) {
        require MT::Permission;
        no warnings 'once';
        no warnings 'redefine';
        $saved_permission_to_hash = \&MT::Permission::to_hash;
        *MT::Permission::to_hash = \&new_permission_to_hash;
    }
    MT->add_plugin($plugin);
    if ($MT::DebugMode) {
        require MT::Util::Log;
        require Data::Dumper;
        MT::Util::Log->init();
    }
}

sub instance { $plugin; }

{
    my $_clear_all_permissions;

    sub new_all_permissions {
        my $class = shift;

        my $driver = $class->driver;
        return {} unless $driver && $driver->table_exists($class);

        if (exists $driver->{ct_permissions} && ref($driver->{ct_permissions}) eq 'HASH' && !$_clear_all_permissions) {
            # MT::Util::Log->info('[new_all_permissions]:return cache') if $MT::DebugMode;
            return $driver->{ct_permissions};
        }
        # MT::Util::Log->info('[new_all_permissions]:no cache') if $MT::DebugMode;

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
        $_clear_all_permissions = 0;
        return \%all_permission;
    }
}

{
    require MT::Request;
    sub new_permission_to_hash {
        my $perms = shift;
        my $hash  = {};

        my $r = MT::Request->instance;
        my $key = ref($perms) eq 'MT::Permission' && $perms->id() ? '__perm_hash_' . $perms->id() : '';
        if ($key && exists $r->{__stash}{$key}) {
            # MT::Util::Log->info('[to_hash]:found cache ' . $key) if $MT::DebugMode;
            return $r->{__stash}{$key};
        }
        my $all_perms = MT::Permission->perms();
        foreach (@$all_perms) {
            my $perm = $_->[0];
            $perm = 'can_' . $perm;
            $hash->{"permission.$perm"} = $perms->$perm();
        }
        # MT::Util::Log->info('[to_hash]:create cache ' . $key) if $key;
        $r->{__stash}{$key} = $hash if $key;
        $hash;
    }
}

sub hdlr_tmpl_param_edit_role {
    my ($cb, $app, $param, $tmpl) = @_;

    # 差し替え
    my $tokens = $plugin->load_tmpl('modify_edit_role_ct.tmpl')->tokens;
    my $dest_node = $tmpl->getElementById('role-content-type-privileges');
    $dest_node->childNodes($tokens);

    my %ct_permissions = ();
    my @new_loaded_permissions;
    foreach (@{$param->{loaded_permissions}}) {
        if (exists $_->{content_type_unique_id}) {
            my $unique_id = $_->{content_type_unique_id};
            if ($_->{id} =~ m/^manage_content_data/) {
                $_->{type} = 'manage';
            } elsif ($_->{id} =~ m/^create|publish|edit_all|_contentdata:/) {
                $_->{type} = 'content_data';
            } else {
                $_->{type} = 'content_field';
            }
            push @{ $ct_permissions{$unique_id} }, $_;
        }
        else {
            push @new_loaded_permissions, $_;
        }
    }
    foreach (@{$param->{content_type_perm_groups}}) {
        $_->{ct_permissions} = $ct_permissions{$_->{ct_perm_group_unique_id}} || [];
    }
    $_->{loaded_permissions} = \@new_loaded_permissions;
}

1;
