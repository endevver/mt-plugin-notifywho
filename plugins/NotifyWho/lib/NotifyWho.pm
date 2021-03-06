# NotifyWho?! plugin for Movable Type
# Author: Jay Allen, Six Apart (http://www.sixapart.com)
# Released under the Artistic License
#
# $Id: NotifyWho.pm 504 2008-02-28 02:11:03Z jallen $

package NotifyWho;
use strict;
use Data::Dumper;
#use MT::Log::Log4perl qw( l4mtdump ); use Log::Log4perl qw( :resurrect );
###l4p our $logger = MT::Log::Log4perl->new();

use MT::Util qw( is_valid_email );
use MT::Entry;

# record_recipients
#
# This is the callback handler for MT::App::CMS::post_run.  It
# short-circuits unless the mode is send_notify in which case it is
# responsible for recording the recipients of the sent entry notifications.
sub record_recipients {
    my $plugin = shift;
    my ($cb, $app) = @_;
    return unless $app->mode eq 'send_notify';
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    ###l4p $logger->info('About to record NotifyWho recipients!');

    if (    defined $app->errstr
        and $app->errstr ne ''
        and $app->errstr !~ m{This\s+shouldn.t\s+happen.*Text/Wrap.pm} ) {
        ###l4p $logger->error('Not recording NotifyWho recipients due to an '
        ###l4p              .'error in sending mail: ', $app->errstr);
        return;
    }

    my $entry_id = $app->param('entry_id');

    # If this entry is being published, then the entry status is published,
    # and this is the last notification that NotifyWho will send. If the
    # entry is unpublished and the $app->mode is "send_notify", then we're
    # sending notification of a draft entry. Don't record recipients because
    # NotifyWho may send notifications again, when the entry is published.
    my $entry = MT->model('entry')->load($entry_id);
    if ($entry->status == MT::Entry::HOLD) {
        ###l4p $logger->info('Not recording NotifyWho recipients because the entry '
        ###l4p     . 'creation email was just sent. (Recipients are saved when the '
        ###l4p     . '"published" email is sent.)');
        return;
    }

    my %recipients;
    if ($app->param('send_notify_list')) {
        %recipients = map { $_->email => 1 }
            $plugin->runner('_blog_subscribers');
    }

    if ($app->param('send_notify_emails')) {
        my @addr = split /[\n\r\s,]+/, $app->param('send_notify_emails');
        $recipients{$_} = 1 foreach @addr;
    }

    ###l4p $logger->debug('$app->{query}: ', l4mtdump(\$app->{query}));
    ###l4p $logger->info('Recording NotifyWho recipients!');
    ###l4p $logger->debug(l4mtdump(\%recipients));

    require NotifyWho::Notification;
    NotifyWho::Notification->save_multiple(
        {
            blog_id     => $app->blog->id,
            entry_id    => $entry_id,
            recipients  => [keys %recipients]
        }
    );
}

# entry_notify_param
#
# This is the callback handler for "share" (send notification) screen
# (MT::App::CMS::template_param.entry_notify). It fills in the default
# values from the NotifyWho configuration and adds sections for previous
# recipients as well as a clickable list of possible recipients.
sub entry_notify_param {
    my $plugin = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    $plugin->runner('_notification_screen_defaults', \@_);

    my $previous = $plugin->runner('_previous_recipients', \@_);

    $plugin->runner('_possible_recipients', [@_, $previous]);
}

# edit_entry_param
#
# This is the callback handler for edit entry screen.
# (MT::App::CMS::template_param.edit_entry). It provides an override for
# auto-notifications and displays the current auto-notify setting.
sub edit_entry_param {
    my $plugin = shift;
    my ($cb, $app, $tmpl_ref) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    $plugin->runner('_automatic_notifications', \@_);

}

# photog_gallery_template_param
#
# The Photo Gallery plugin creates new entries, but not with the traditional
# Edit Entry interface; a special photo upload/batch photo upload tool does
# the work. Insert the `auto_notifications` input so that NotifyWho can send
# notifications, if configured to do so.
sub photo_gallery_template_param {
    my $plugin = shift;
    my ($cb, $app, $param, $tmpl) = @_;

    my $node = $tmpl->createTextNode(
        '<input type="hidden" name="auto_notifications" value="1" />'
    );

    $tmpl->insertAfter(
        $node,
        ( $tmpl->getElementById('title')        # The batch upload screen
          || $tmpl->getElementById('file_name') # The popup dialog screen
        )
    );
}

# autosend_entry_notify_bulk
#
# This is the handler for the cms_post_bulk_save.entries callback which handles
# automatic entry notifications if enabled and configured.
sub autosend_entry_notify_bulk {
    my ($plugin, $cb, $app, $objects) = @_;
    my $debug = $plugin->get_config_value('nw_debug_mode');
    log_message('Running bulk save', $debug, 'info', $app->blog->id);
    for my $o (@$objects) {
        autosend_entry_notify($plugin, $cb, $app, ${$o}{current}, ${$o}{original}, 1)
    }
}

# autosend_entry_notify
#
# This is the handler for the cms_post_save.entry callback which handles
# automatic entry notifications if enabled and configured.
sub autosend_entry_notify {
    my ($plugin, $cb, $app, $entry, $orig_obj) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    # check if this sub was called by the cms_post_bulk_save.entries callback
    # if so, we don't need to check for the "auto_notifications" toggle
    my $bulk = shift;
    unless ($bulk) {

        my $send_status = $app->request('notifywho_already_sent') || {};
        return if $send_status->{sent};

        ###l4p $logger->debug('$entry: ', l4mtdump($entry));
        ###l4p $logger->debug('$orig_obj: ', l4mtdump($orig_obj));

        # On the Edit Entry screen, Notify Who adds a switch to enable/disable
        # notifications for that entry, called "auto_notifications".
        # The "auto_notifications" parameter is set only if this new entry is
        # created within the MT admin interface. If this is an entry created from
        # the Community Pack, then the parameter doesn't exist.
        if ( !$app->isa('MT::App::Community')
            && !$app->{query}->param('auto_notifications')
        ) {
            ###l4p $logger->debug('Auto-notifications are DISABLED for the current entry.');
            return;
        }

    }

    ###l4p $logger->debug('Auto-notifications are ENABLED. Commencing now...');

    # Check to see if this function is enabled in plugin settings
    my $blog = $entry->blog;
    if (!$blog) {
        my $msg = "No blog in context in NotifyWho post_save_entry callback";
        require MT::Log;
        $app->log({
            message  => $msg,
            level    => MT::Log::ERROR(),
            class    => 'system',
            category => 'notifywho'
        });
        ###l4p $logger->error($msg);
        return;
    }
    my $blogarg = 'blog:'.$app->blog->id;
    my $notify_list
        = $plugin->get_config_value('nw_entry_list', $blogarg) || 0;
    my $notify_emails
        = $plugin->get_config_value('nw_entry_emails', $blogarg) || '';
    if ($plugin->get_config_value('nw_entry_author', $blogarg)) {
        {
            my $author = MT::Author->load($entry->author_id);
            my $author_email = $author->email || '' if $author;
            last unless $author_email;
            if($notify_emails) {
                $notify_emails .= ',';
            }
            $notify_emails .= $author_email;
        }
    }
    my $message
        = $plugin->get_config_value('nw_entry_message', $blogarg) || '';
    my $entry_text_cfg
        = $plugin->get_config_value('nw_entry_text', $blogarg) || 0;

    my $send_excerpt    = ( $entry_text_cfg eq 'excerpt' )  ? 1 : 0;
    my $send_body       = ( $entry_text_cfg eq 'full' )     ? 1 : 0;

    my $notify_upon_create
        = $plugin->get_config_value('nw_entry_created_auto', $blogarg) || 0;

    my $has_recipients = $notify_list || $notify_emails;
    ###l4p $logger->debug(sprintf
    ###l4p  '$has_recipients, $notify_list, $notify_emails: %s, %s, %s,',
    ###l4p   $has_recipients, $notify_list, $notify_emails);

    if (! $has_recipients) {
        ###l4p $logger->debug('NOT ENABLED - No recipients specified');
        return;
    }
    elsif ( _has_previous_notifications($entry->id) ) {
        ###l4p $logger->debug('NOTIFICATIONS PREVIOUSLY SENT - Aborting send notify');
        return;
    }
    elsif ( ! _is_new_entry_or_just_published($notify_upon_create, $entry, $orig_obj) ) {
        ###l4p $logger->debug('NOT A NEW OR NEWLY PUBLISHED ENTRY OR NOTIFY ON CREATE TURNED OFF - Aborting send notify');
        return;
    }

    my $msg = 'Preparing to send notifications to ' . $notify_emails . ( $notify_list ? ' and the blog list.' : '' );
    ###l4p $logger->debug($msg);

    # Set params for MT::App::CMS::send_notify()
    $app->mode('send_notify');
    $app->param('send_notify_list', $notify_list);
    $app->param('send_notify_emails', $notify_emails);
    $app->param('entry_id', $entry->id);
    $app->param('message', $message) if $message;
    $app->param('send_excerpt', $send_excerpt);
    $app->param('send_body', $send_body);

    # Execute MT::App::CMS::send_notify()
    # $app may be an MT::App or it could be MT::App::Community, if the entry
    # is created from a public form.
    my $rc = MT::App::CMS::send_notify($app);
    ###l4p $logger->debug('Notifications sent.');
    delete $app->{$_} foreach (qw(redirect redirect_use_meta));
    ###l4p $logger->error($app->errstr) if $app->errstr;
    # todo: make this store value per entry to properly handle bulk saves
    unless ($bulk) {
      $app->request('notifywho_already_sent', { sent => 1 });
    }
    $rc;
}

# add_notifywho_js
#
# This is the handler for the MT::App::CMS::template_source.header callback
# which is responsible for inserting NotifyWho's javascript file into the
# header
sub add_notifywho_js {
    my $plugin = shift;
    my ($cb, $app, $tmpl) = @_;
    ##l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    my $js_include = <<TMPL;
<mt:setvarblock name="js_include" append="1">
<script type="text/javascript" src="<mt:var name="static_uri">plugins/NotifyWho/notifywho.js?v=<mt:var name="mt_version" escape="url">"></script>
</mt:setvarblock>
TMPL
    $$tmpl = $js_include . $$tmpl;
}

# cb_mail_filter
#
# This is the handler for the mail_filter callback which is used currently
# only to modify the mail headers on Comment/Trackback notifications.
sub cb_mail_filter {
    my $plugin = shift;
    my ($cb, %params) = @_;
    my @recipients;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    ###l4p $logger->info('HANDLING ', $params{id});

    if ($params{id} =~ m!new_(comment|ping)!) {

        # Get the config for this blog
        my $blog = $plugin->current_blog();
        ###l4p $logger->debug('$blog: ', l4mtdump($blog));

        my $config = $plugin->get_config_hash('blog:' . $blog->id);
        ###l4p $logger->debug('$config: ', l4mtdump($config));

        @recipients
            = $config->{nw_fback_author} ? $params{headers}->{To} : ();

        if (exists $config->{nw_fback_emails} and $config->{nw_fback_emails}){
            my @others = split(/[\r\n\s,]+/, $config->{nw_fback_emails});
            push(@recipients, @others);
        }

        if (exists $config->{nw_fback_list} and $config->{nw_fback_list}) {
            push(@recipients, map { $_->email }
                $plugin->runner('_blog_subscribers'));
        }
    }
    # When running MT::App::CMS::AddressBook::send_notify, skip the first
    # attempt to send a notification where only the "to" address is set and all
    # other notifications have not been set. (Found in
    # `unless ( exists $params{from_address} ) {`.) Notify Who handles all
    # notification addresses, therefore this first check isn't needed, so skip
    # it.
    elsif (
        $params{id} eq 'notify_entry'
        && $params{headers}->{To}
        && !$params{headers}->{Bcc}
    ) {
        return 0;
    }

    ###l4p $logger->debug('Intended recips: ', (join ', ',@recipients));
    ###l4p $logger->debug('DELETING FROM TO: ', delete $params{headers}->{To});
    ###l4p $logger->debug('DELETING FROM BCC: ', delete $params{headers}->{Bcc});

    if (@recipients) {
        # The Config Directive EmailNotificationBcc is enabled by default.
        if (MT->instance->config('EmailNotificationBcc')) {
            $params{headers}->{Bcc} = \@recipients;
            # Normally we would set the "To" header to the author, just so
            # that the email header would be complete. But, we don't want
            # to always notify the author, and the author can be in
            # @recipients/BCC, anyway.
            $params{headers}->{To} = '';
        } else {
            $params{headers}->{To} = \@recipients;
        }
    }

    ###l4p $logger->debug('NEW TO: ', l4mtdump($params{headers}->{To}));
    ###l4p $logger->debug('NEW BCC: ', l4mtdump($params{headers}->{Bcc}));
    ###l4p $logger->debug('MAIL PARAMS: ', l4mtdump(\%params));

    return 1;
}

sub _automatic_notifications {
    my $plugin = shift;
    my ($cb, $app, $param, $tmpl) = @{$_[0]};
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    # hide the toggle on published or scheduled entries
    return if $param->{status} == 2 || $param->{status} == 4;

    my $blogarg = 'blog:'.$app->blog->id;

    my $auto = 0;
    # if “on create” enabled, toggle “Enabled” on new entries
    $auto = $plugin->get_config_value('nw_entry_created_auto', $blogarg) || 0 if ! $param->{status};
    # if “on publish” enabled, toggle “Enabled” on all entries (new and draft, as otherwise we returned already)
    $auto = 1 if $plugin->get_config_value('nw_entry_auto', $blogarg);

    my $disclaim = '';
    # if “on create” disabled but “on publish” enabled, notifications not always sent on new entry
    # make clear notifications will only be sent if set to published/scheduled
    $disclaim = ' (upon publish or scheduling)'
        if $auto and ! $plugin->get_config_value('nw_entry_created_auto', $blogarg);

    my $hiddeninput = '<input type="hidden" name="auto_notifications" id="auto_notifications" value="' . $auto . '" />';
    my $currentSetting = $auto ? 'Enabled' : 'Disabled';
    my $node = $tmpl->createTextNode(<<EOM);
        <p>Automatic notifications for this entry$disclaim are: <a href="javascript:void(0)" onclick="toggle_notifications(); return false;" id="auto_notifications_link">$currentSetting</a>$hiddeninput</p>
EOM

    # if forced option set, hide the toggle by overwriting node
    # but keep the hidden form input to keep notifications working,
    my $force = $plugin->get_config_value('nw_entry_force', $blogarg) || 0;
    $node = $tmpl->createTextNode($hiddeninput) if ($force);

    $tmpl->insertAfter($node, $tmpl->getElementById('keywords'));
}

sub _previous_recipients {
    my $plugin = shift;
    my ($cb, $app, $param, $tmpl) = @{$_[0]};
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    my $q = $app->param;
    my $entry_id = $q->param('entry_id') or return;
    my $entry = MT::Entry->load($entry_id);

    my $author = MT::Author->load($entry->author_id) if $entry;
    return unless $entry and $author;

    my %subscribers = map { $_->email => 1 }
        $plugin->runner('_blog_subscribers');

    my $recipients = 'None';
    my (%past_recipients);
    if (my $sent
        = $plugin->runner('_sent_notifications', $entry_id)) {
        my $notify_list_used = 0;
        foreach (@$sent) {
            if ($subscribers{$_->email}) {
                $notify_list_used = 1;
                next;
            }
            next if $_->email eq $author->email;
            if ($_->list) {
                $past_recipients{'Notification list subscribers'} = 1;
            }
            else {
                $past_recipients{$_->email} = 1;
            }
        }
        my @rr = sort keys %past_recipients;
        unshift(@rr, 'Notification list subscribers') if $notify_list_used;
        $recipients = join(', ', @rr);
    }

    my $new = $tmpl->createElement(
        'app:setting',
        {
            id => "previous_recipients",
            label => "Previous Recipients",
            label_class => "top-label",
            show_hint => "1",
            hint => "The addresses listed above have been sent a notification previously for this entry.",
        }
    );
    $new->innerHTML($recipients);
    $tmpl->insertBefore($new, $tmpl->getElementById('send_notify_list'));
    \%past_recipients;
}

sub _possible_recipients {
    my $plugin = shift;
    my ($cb, $app, $param, $tmpl, $previous) = @{$_[0]};
    ##l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    my $q        = $app->param;
    my $entry_id = $q->param('entry_id') or return;
    my $entry    = MT::Entry->load($entry_id) or return;

    my $author = MT::Author->load($entry->author_id) if $entry;
    return unless $author;

    my %subscribers = map { $_->email => 1 }
                    $plugin->runner('_blog_subscribers');

    my $blog_arg = { blog_id => $entry->blog_id };

    my %possible;
    require NotifyWho::Notification;
    if (NotifyWho::Notification->count($blog_arg)) {

        my $iter = NotifyWho::Notification->load_iter($blog_arg);
        # $logger->debug(NotifyWho::Notification->errstr)
        #     if !$iter and NotifyWho::Notification->errstr;
        while (my $recip = $iter->()) {
            next if  $recip->email eq $author->email
                 or  $previous->{$recip->email}
                 or  $subscribers{$recip->email};
            $possible{$recip->email} = 1;
        }
    }
    else {
        ###l4p $logger->info('No notifications found for blog ', $entry->blog_id);
    }

    if (keys %possible) {
        my @possible = map { '<a href="javascript:void(0)" onclick="add_recipient(\''.$_.'\');return false;">[+] '.$_.'</a>' } keys %possible;
        my $possible_recipients = join(', ', @possible);

        my $new = 'Previous recipients from this blog (excluding notification list members) Click to add:<ul><li>'.$possible_recipients.'</li></ul>';

        my $node = $tmpl->getElementById('send_notify_list');
        my $html = $node->innerHTML;
        $node->innerHTML(join("\n",$html,"<div>$new</div>"));
    }


}

# Update the contents of the Send a Notification popup dialog, found when
# clicking the Share link on an Entry or Page.
sub _notification_screen_defaults {
    my $plugin = shift;
    my ($cb, $app, $param, $tmpl) = @{$_[0]};
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    my $entry_id = $app->param('entry_id') or return;
    my $entry = MT::Entry->load($entry_id);

    my $blogarg = 'blog:'.$app->blog->id;
    my $cfg = $plugin->get_config_hash($blogarg) || {};

    ###l4p $logger->debug('CFG: ', l4mtdump($cfg));

    {
        my $input = $tmpl->getElementById('send_notify_list');
        my $html = $input->innerHTML;
        $html =~ s{rows="3"}{rows="2"}; # Shorten
        $html =~ s{lines-4}{lines-3}; # Shorten

        $cfg->{nw_entry_list}
            or $html =~ s/ checked="checked"//; # Remove check

        my $notify_emails = '';
        if ($cfg->{nw_entry_author}) {
            my $author = MT::Author->load($entry->author_id) if $entry;
            $notify_emails = $author->email if $author;
        }
        if ($cfg->{nw_entry_emails}) {
            if($notify_emails) {
                $notify_emails .= ',';
            }
            $notify_emails .= $cfg->{nw_entry_emails};
        }
        $notify_emails
            and $html =~ s{(\</textarea\>)}{$notify_emails$1}x;

        $input->innerHTML($html);
    }

    if ($cfg->{nw_entry_message}) {
        my $input = $tmpl->getElementById('message');
        my $html = $input->innerHTML;
        $html =~ s{rows="4"}{rows="2"}; # Shorten
        $html =~ s{lines-5}{lines-3}; # Shorten
        $html =~ s{(\</textarea\>)}{$cfg->{nw_entry_message}$1};
        $input->innerHTML($html);
    }

    if ($cfg->{nw_entry_text}) {
        my $input = $tmpl->getElementById('send_content');
        my $html = $input->innerHTML;

        my $marker = $cfg->{nw_entry_text} eq 'full'    ? "send_body"
                   : $cfg->{nw_entry_text} eq 'excerpt' ? "send_excerpt"
                                                        : undef;
        if ($marker) {
            $html =~ s{(id="$marker")}{$1 checked="checked"};
            $input->innerHTML($html);
        }
    }
}

sub _blog_subscribers {
    my $plugin = shift;
    my $blog_id = shift;
    if (!$blog_id) {
        my $blog = $plugin->current_blog() or return;
        $blog_id = $blog->id;
    }
    require MT::Notification;
    return (MT::Notification->load({blog_id => $blog_id}));
}

sub _is_new_entry_or_just_published {
    my ($notify_upon_create, $entry, $orig_obj) = @_;

    return (
        # Notify of new entry
        ($notify_upon_create && (!$orig_obj || !$orig_obj->id))
        ||
            # Is now published or scheduled
            ($entry->status == MT::Entry::RELEASE || $entry->status == MT::Entry::FUTURE)
            &&
            (
                # Is new entry
                (!$orig_obj || !$orig_obj->id)
                ||
                # Was not published or scheduled
                $orig_obj->status != MT::Entry::RELEASE && $orig_obj->status != MT::Entry::FUTURE
            )
        || 0
    );
}

sub _has_previous_notifications {
    my $entry_id = shift;
    require NotifyWho::Notification;
    return (NotifyWho::Notification->count({entry_id => $entry_id}) || 0);
}

sub _sent_notifications {
    my $plugin = shift;
    my $entry_id = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    ###l4p $logger->debug("Pulling sent notifications for entry ID $entry_id");
    return unless NotifyWho::Notification->count({entry_id => $entry_id});

    # Load from table
    require NotifyWho::Notification;
    my @notes = NotifyWho::Notification->load({entry_id => $entry_id});
    if (! @notes and NotifyWho::Notification->errstr) {
        my $err = sprintf('Error loading %s for entry ID %s: %s',
                    __PACKAGE__, $entry_id, NotifyWho::Notification->errstr);
        require MT;
        MT->log($err);
        ##l4p $logger->fatal($err);
        ##l4p $logger->fatal(  message  => $err,
        ##l4p                 class    => 'notifications', # TODO Check that this is a valid log class
        ##l4p                 metadata => $entry_id);
        return;
    }
    return @notes ? \@notes : undef;
}

# sub _app_param_dump {
#    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
#     $logger->debug(Dumper($_[3]));
# }

1;

__END__

