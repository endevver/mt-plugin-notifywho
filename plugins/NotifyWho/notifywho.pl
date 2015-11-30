# NotifyWho?! plugin for Movable Type
# Author: Jay Allen, Six Apart (http://www.sixapart.com)
# Released under the Artistic License
#
# $Id: notifywho.pl 177 2007-01-19 11:59:32Z jallen $

package MT::Plugin::NotifyWho;

use strict;
use 5.006;    # requires Perl 5.6.x
use MT 3.2;   # requires MT 3.2 or later
use warnings;

use base 'MT::Plugin';

our $VERSION = "1.03";
(our $PLUGIN_MODULE = __PACKAGE__) =~ s/^MT::Plugin:://;

my $plugin;
MT->add_plugin($plugin = __PACKAGE__->new({
    name => 'Notify Who?!',
    version => $VERSION,
	key => 'notifywho',
    author_name => 'Jay Allen',
    author_link => 'http://jayallen.org/',
    plugin_link => 'http://jayallen.org/projects/notifywho/',
    description => '<MT_TRANS phrase="NOTIFYWHO_PLUGIN_DESCRIPTION">',
    doc_link => 'http://jayallen.org/projects/notifywho/docs/v'.$VERSION,
    l10n_class => 'NotifyWho::L10N',
    blog_config_template => 'blog_config.tmpl',
    settings => new MT::PluginSettings([
        ['notifywho_author', { Default => 1 }],
        ['notifywho_others', { Default => '' }],
    ]),
}));

# Adding L10N bootstrapping for MT 3.2
MT->add_callback('MT::App::CMS::pre_run', 1, $plugin, \&add_l10n) if $MT::VERSION < 3.3;

# Allows external access to plugin object: MT::Plugin::MyPlugin->instance
sub instance { $plugin }

sub runner {
    shift if ref($_[0]) eq ref($plugin);
    my $method = shift;
    eval "require $PLUGIN_MODULE";
    if ($@) { print STDERR $@; $@ = undef; return 1; }
    my $method_ref = $PLUGIN_MODULE->can($method);
    return $method_ref->($plugin, @_) if $method_ref;
    die $plugin->translate('Failed to find '.$PLUGIN_MODULE.'::[_1]', $method);
}

sub init_app {
	my $plugin = shift;
	$plugin->SUPER::init_app(@_);
	my ($app) = @_;
	require MT::Util;

	# Capture for later use and override the comment and ping notification methods
	# We will be calling these on our own terms (i.e. with modified recipients) later on.
	if ($app->isa('MT::App::Comments')) {
		{
			local $SIG{__WARN__} = sub {  }; 
		    $plugin->{notify_method} = \&MT::App::Comments::_send_comment_notification;
		    *MT::App::Comments::_send_comment_notification = sub { runner('_comment_notify_handler', @_) };
		}  
	} elsif ($app->isa('MT::App::Trackback')) {
		{
			local $SIG{__WARN__} = sub {  }; 
		    $plugin->{notify_method} = \&MT::App::Trackback::_send_ping_notification;
		    *MT::App::Trackback::_send_ping_notification = sub { runner('_ping_notify_handler', @_) };
		}  
	}
}

sub save_config {

    my $plugin = shift;
    my ($param, $scope) = @_;
	require MT::Util;

	# Specifically set notifywho_author to 0 if not set
	$param->{notifywho_author} = $param->{notifywho_author} ? $param->{notifywho_author} : 0; 

	# Upon saving, we check all emails to make sure they are valid and unique
	my %seen;
	my @emails = split(/[,\s]+/, $param->{notifywho_others});
	@emails = grep(! $seen{$_}++ && MT::Util::is_valid_email($_), @emails);
	$param->{notifywho_others} = join(', ',@emails);

	# Send the params to mommy for safe keeping
    $plugin->SUPER::save_config($param, $scope);
}

# We use an MT::App::CMS::pre_run callback to
# bootstrap the plugin's localization module
# and then handle the translate calls if needed.
sub add_l10n {
    my ($cb,$app) = @_;
    (my $lang = $app->current_language) =~ s/-/_/g;
    eval "require NotifyWho::L10N::$lang";
}
sub translate {
    my $plugin = shift;
    return $MT::VERSION < 3.3   ?   MT->instance->translate(@_)
                                :   $plugin->SUPER::translate(@_);
}

1;
