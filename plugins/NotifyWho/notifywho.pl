package MT::Plugin::NotifyWho;
# A plugin for Movable Type
# Released under the Artistic License
# $Id: notifywho.pl 504 2008-02-28 02:11:03Z jallen $
use strict; use 5.006; use warnings; use Data::Dumper;
use lib './lib';
use lib './extlib';
use Carp qw(croak confess);

use MT 4.0;
use MT::Plugin;
use base 'MT::Plugin';

use MT::Mail;
use NotifyWho::Notification;

# Public version number
our $VERSION = "2.1.5";

# Development revision number
#our $Revision = ('$Revision: 504 $ ' =~ /(\d+)/);
#my $beta_notice = " (Beta 1, revision $Revision)";

our ($plugin, $PLUGIN_MODULE, $PLUGIN_KEY);
MT->add_plugin($plugin = __PACKAGE__->new({
    name            => 'Notify Who?!',
    version         => $VERSION,
    schema_version  => 2,
    key             => plugin_key(),
    author_name     => 'Jay Allen',
    author_link     => (our $JA = 'http://jayallen.org'),
    plugin_link     => 'https://github.com/endevver/mt-plugin-notifywho',
    description     => '<MT_TRANS phrase="NOTIFYWHO_PLUGIN_DESCRIPTION">',
    l10n_class      => 'NotifyWho::L10N',
    blog_config_template => 'blog_config.tmpl',
    settings => new MT::PluginSettings([
        ['nw_fback_author',         { Default => 1 }],
        ['nw_fback_emails',         { Default => '' }],
        ['nw_fback_list',           { Default => 0 }],
        ['nw_entry_force',          { Default => 0 }], # disallow user from disabling
        ['nw_entry_auto',           { Default => 0 }], # entry publication
        ['nw_entry_created_auto',   { Default => 0 }], # entry creation
        ['nw_entry_author',         { Default => 0 }],
        ['nw_entry_list',           { Default => 0 }],
        ['nw_entry_emails',         { Default => '' }],
        ['nw_entry_message',        { Default => '' }],
        ['nw_entry_text',           { Default => 'none' }],
        # Legacy settings
        ['nw_entry_send_excerpt',   { Default => undef }],
        ['nw_entry_send_body',      { Default => undef }],
        ['notifywho_author',        { Default => undef }],
        ['notifywho_others',        { Default => undef }],
    ]),
}));

# use MT::Log::Log4perl qw( l4mtdump ); use Log::Log4perl qw( :resurrect );
###l4p our $logger = MT::Log::Log4perl->new();

sub init_registry {
    my $plugin = shift;

    # unless ($logger) {
    #     require MT::Log::Log4perl;
    #     import MT::Log::Log4perl qw(l4mtdump);
    #     $logger = MT::Log::Log4perl->new();
    # }

    # Register callbacks with MT
    $plugin->registry({
        object_types  => { 'nwnotification' => 'NotifyWho::Notification' },
        callbacks => {

            # If enabled, this callback handles the sending of notifications
            # after an entry is published by Batch Edit or Manage Entries screen.
            'cms_post_bulk_save.entries'
                            => sub { runner('autosend_entry_notify_bulk', @_) },

            # If enabled, this callback handles the sending of notifications
            # after an entry is newly published.
            'cms_post_save.entry'
                            => sub { runner('autosend_entry_notify', @_) },

            # This callback handles sending notifications for an entry created
            # through the API, such as the Community Pack does.
            'api_post_save.entry'
                            => sub { runner('autosend_entry_notify', @_) },

            # This callback handles notification modifications for feedback
            # since these routines are not as friendly as send_notify()
            'mail_filter'
                            => sub { runner('cb_mail_filter', @_) },

            # This callback handler is the main modifier of the share
            # (send_notify) UI modal dialog, adding previous recipients and
            # a clicakable list of possible recipients
            'MT::App::CMS::template_param.entry_notify'
                            => sub { runner('entry_notify_param', @_) },

            # This handler inserts a switch for disabling automatic entry
            # notifications on a per entry basis
            'MT::App::CMS::template_param.edit_entry'
                            => sub { runner('edit_entry_param', @_) },

            # This handler adds the automatic entry notification flag to the
            # Photo Gallery plugin's batch upload screen.
            'MT::App::CMS::template_param.batch_upload'
                            => sub { runner('photo_gallery_template_param', @_) },

            # This handler adds the automatic entry notification flag to the
            # Photo Gallery plugin's popup upload screen.
            'MT::App::CMS::template_param.edit_photo'
                            => sub { runner('photo_gallery_template_param', @_) },

            # This handler inserts NotifyWho's javascript into the application
            # pages' header section notifications on a per entry basis
            'MT::App::CMS::template_source.header'
                            => sub { runner('add_notifywho_js', @_) },

            # This handler records the notification recipients in the database
            # for information on previous recipients and for the possible
            # recipient list for future entries.
            'MT::App::CMS::post_run'
                            => sub { runner('record_recipients', @_) },

            # This handler does nothing except report that a save happened.
            # 'NotifyWho::Notification::post_save'
            #                 => \&notification_post_save,
        },
    });
}

# sub init_request {
#     my $plugin = shift;
#     my ($app) = @_;
#     ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
#
#     # TODO Disable ThrottleSeconds disabling
#     $app->config('ThrottleSeconds', 0);
#
#     # Uncomment to set test configuration
#     # $plugin->test_config($app);
# }

sub load_config {
    my $plugin = shift;
    my ($param, $scope) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    $plugin->SUPER::load_config(@_);
    $plugin->convert_config($param);
    ##l4p $logger->debug("\$param for scope $scope: ", l4mtdump($param));
    $param;
}

sub save_config {
    my $plugin = shift;
    my ($param, $scope) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    require MT::Util;

    $plugin->convert_config($param);

    # Specifically set notifywho_author to 0 if not set
    $param->{nw_fback_author}       ||= 0;
    $param->{nw_entry_list}         ||= 0;

    # Upon saving, we check all emails to make sure they are valid and unique
    foreach my $key (qw(nw_fback_emails nw_entry_emails)) {
        next unless defined $param->{$key} and $param->{$key} ne '';
        my (%seen, @emails) = ();
        @emails = split(/[\n\r\s,]+/, $param->{$key});
        @emails
            = grep(! $seen{$_}++ && MT::Util::is_valid_email($_), @emails);
        $param->{$key} = join(', ',@emails);
        ##l4p $logger->debug("FINAL $key VALUE: ", $param->{$key});

    }

    # Send the params to mommy for safe keeping
    $plugin->SUPER::save_config($param, $scope)
        or die "Could not save config: ".$plugin->SUPER::errstr;
}

sub convert_config {
    my ($plugin, $hash) = @_;
    return $hash unless $hash and ref $hash;

    $hash->{nw_fback_author} = delete $hash->{notifywho_author}
        if defined $hash->{notifywho_author};

    $hash->{nw_fback_emails} = delete $hash->{notifywho_others}
        if  defined $hash->{notifywho_others}
        and ! exists $hash->{nw_fback_emails};

    if (defined $hash->{nw_entry_send_body}) {
        delete $hash->{nw_entry_send_body};
        $hash->{nw_entry_text} = 'full';
    }

    if (defined $hash->{nw_entry_send_excerpt}) {
        delete $hash->{nw_entry_send_excerpt};
        $hash->{nw_entry_text} = 'excerpt';
    }
    $hash;
}

sub runner {
    ##l4p $logger->debug(sprintf 'IN RUNNER ARG: %s %s', ref $_, $_) foreach @_;

    shift if ref($_[0]) eq ref($plugin);
    my $method = shift;
    $PLUGIN_MODULE = plugin_module();
    eval "require $PLUGIN_MODULE";
    if ($@) {
        # STDERR isn't necessarily an obvious place to look for things...
        # print to the MT Activity Log, too.
        print STDERR $@;
        MT->log("NotifyWho error: ".$@);
        $@ = undef;
        return 1;
    }

    ##l4p $logger->debug(sprintf 'Looking for %s in module %s', $method, $PLUGIN_MODULE);

    my $method_ref = $PLUGIN_MODULE->can($method);
    return $method_ref->($plugin, @_) if $method_ref;
    croak $plugin->translate(
        'Failed to find '.$PLUGIN_MODULE.'::[_1]', $method);
    ##l4p $logger->logcroak($plugin->translate(
    ##l4p    'Failed to find '.$PLUGIN_MODULE.'::[_1]', $method));
}

sub translate {
    my $plugin = shift;
    return $plugin->SUPER::translate(@_);
}

sub current_blog {
    my $self = shift;
    my $app = MT->instance or return;
    my $blog = $app->blog;
    if (!$blog) {
        my $msg
            = 'No blog in context in '.__PACKAGE__.'::current_blog. Called by '.(caller(1))[3];
        require MT::Log;
        $app->log({
            message  => $msg,
            level    => MT::Log::ERROR(),
            class    => 'system',
            category => 'notifywho'
        });
        ##l4p $logger->error($msg);
    }
    return $blog;
}

# sub notification_post_save {
#     my ($cb, $obj, $orig_obj) = @_;
#     ##l4p $logger->trace('Saying hell from the new callback!');
#     # Move me to the right place please...
# }

sub plugin_module   {
    ($PLUGIN_MODULE = __PACKAGE__) =~ s/^MT::Plugin:://;
    return $PLUGIN_MODULE; }

sub plugin_key      {
    ($PLUGIN_KEY = lc(plugin_module())) =~ s/\s+//g;  return $PLUGIN_KEY; }

1;

__END__

