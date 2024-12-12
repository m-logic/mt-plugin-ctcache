package MT::Plugin::CTCache;

use strict;
use MT;
use MT::ContentType;
use MT::Permission;
use MT::Plugin;

use base qw( MT::Plugin );

use constant DEBUG => 0;

my $PLUGIN_NAME = 'CTCache';
my $VERSION = '0.31';
my $plugin = new MT::Plugin::CTCache({
    name => $PLUGIN_NAME,
    version => $VERSION,
    description => 'This plugin caches some internal data of Movable Type that is repeated referrenced.',
    author_name => 'M-Logic, Inc.',
    author_link => 'http://m-logic.co.jp/',
});

my $saved_all_permissions;
my $saved_permission_to_hash;

if (MT->version_number >= 7.1) { # required MT7.1
    ## 1: MT::ContentType::all_permissions
    ##    version < 8.10
    if (MT->version_number < 8.1) {
        unless($saved_all_permissions) {
            require MT::ContentType;
            no warnings 'once';
            no warnings 'redefine';
            $saved_all_permissions = \&MT::ContentType::all_permissions;
            *MT::ContentType::all_permissions = \&new_all_permissions;
        }
    }
    ## 2: Cache MT::Permission::to_hash
    unless($saved_permission_to_hash) {
        require MT::Permission;
        no warnings 'once';
        no warnings 'redefine';
        $saved_permission_to_hash = \&MT::Permission::to_hash;
        *MT::Permission::to_hash = \&new_permission_to_hash;
    }

    ## 3: Improve edit_role screen.
    MT->add_callback(
        'template_param.edit_role', 10,
        MT->component('core'),
        \&hdlr_tmpl_param_edit_role
    );

    MT->add_plugin($plugin);
    if (DEBUG) {
        require MT::Util::Log;
        require Data::Dumper;
        MT::Util::Log->init();
    }
}

sub instance { $plugin; }

## 1: MT::ContentType::all_permissions
##    version < 8.10
{
    my $_clear_all_permissions;

    sub new_all_permissions {
        my $class = shift;

        my $r = MT::Request->instance;
        my $key = '__ctcache_all_permissions_';
        if (exists $r->{__stash}{$key} && !$_clear_all_permissions) {
            MT::Util::Log->info('[all_permissions]:return cache ' . $key) if DEBUG;
            return $r->{__stash}{$key};
        }
        MT::Util::Log->info('[new_all_permissions]:' . ($_clear_all_permissions ? 'clear cache' : 'no cache')) if DEBUG;

        my $driver = $class->driver;
        return {} unless $driver && $driver->table_exists($class);

        require MT::ContentType;
        my @all_permissions;
        # required MT7.1
        my @content_types = MT::ContentType::_eval_if_mssql_server_or_oracle( sub { @{ $class->load_all } } );
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
        $_clear_all_permissions = 0;
        return $r->{__stash}{$key} = \%all_permission;
    }
}

## 2: Cache MT::Permission::to_hash
{
    require MT::Request;
    sub new_permission_to_hash {
        my $perms = shift;
        my $hash  = {};

        my $r = MT::Request->instance;
        my $key = ref($perms) eq 'MT::Permission' && $perms->id() ? '__ctcache_perm_hash_' . $perms->id() : '';
        if ($key && exists $r->{__stash}{$key}) {
            MT::Util::Log->info('[to_hash]:return cache ' . $key) if DEBUG;
            return $r->{__stash}{$key};
        }
        my $all_perms = MT::Permission->perms();
        foreach (@$all_perms) {
            my $perm = $_->[0];
            $perm = 'can_' . $perm;
            $hash->{"permission.$perm"} = $perms->$perm();
        }
        MT::Util::Log->info('[to_hash]:create cache ' . $key) if DEBUG;
        $r->{__stash}{$key} = $hash if $key;
        $hash;
    }
}

## 3: Improve edit_role screen.
sub hdlr_tmpl_param_edit_role {
    my ($cb, $app, $param, $tmpl) = @_;

    MT::Util::Log->info('[hdlr_tmpl_param_edit_role]') if DEBUG;

    # replace template
    my $tokens = $plugin->load_tmpl('modify_edit_role_ct.tmpl')->tokens;
    my $dest_node = $tmpl->getElementById('role-content-type-privileges');
    $dest_node->childNodes($tokens);

    # modify $param->{loaded_permissions}
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
    $param->{loaded_permissions} = \@new_loaded_permissions;
}

1;
