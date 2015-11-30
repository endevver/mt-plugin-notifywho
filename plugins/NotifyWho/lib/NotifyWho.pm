package NotifyWho;

use strict;
use MT::Util qw( is_valid_email );

sub _ping_notify_handler {

	my $plugin = shift;
	my ($app, $blog, $entry, $cat, $ping) = @_;

	# Get the config for this blog
    my $config = $plugin->get_config_hash('blog:' . $blog->id);

	# Save author email locally
	my $original_author_email = $entry->author->email;

	# Modify author email to plugin-specified value
	$entry->author->email(
		join(', ', grep($_,
			($config->{notifywho_author} && $entry->author->email ? $entry->author->email : undef), 
			($config->{notifywho_others} ? $config->{notifywho_others} : undef)			
	)));

	# Run original comment notification routine
	&{$plugin->{notify_method}}($app, $blog, $entry, $cat, $ping);

	# Revert author email to original value
	$entry->author->email($original_author_email);
}


sub _comment_notify_handler {

	my $plugin = shift;
    my ($app, $comment, $comment_link, $entry, $blog, $commenter) = @_;

	# Get the config for this blog
    my $config = $plugin->get_config_hash('blog:' . $blog->id);

	# Save author email locally
	my $original_author_email = $entry->author->email;

	# Modify author email to plugin-specified value
	$entry->author->email(
		join(', ', grep($_,
			($config->{notifywho_author} && $entry->author->email ? $entry->author->email : undef), 
			($config->{notifywho_others} ? $config->{notifywho_others} : undef)			
	)));

    if ($MT::VERSION >= 3.3) {        
    	# Run modified comment notification routine which
    	# allows multiple email addresses in the To field.
        $plugin->runner('_send_comment_notification_3_3_mod', $app, $comment, $comment_link, $entry, $blog, $commenter)
    } else {        
    	# Run original comment notification routine
    	&{$plugin->{notify_method}}($app, $comment, $comment_link, $entry, $blog, $commenter);
    }

	# Revert author email to original value
	$entry->author->email($original_author_email);
}


sub _send_comment_notification_3_3_mod {

    my $plugin = shift;
    my $app = shift;
    my ($comment, $comment_link, $entry, $blog, $commenter) = @_;

    return unless $blog->email_new_comments;

    my $commenter_has_comment = MT::App::Comments::_commenter_has_comment($commenter, $entry);
    my $attn_reqd = $comment->is_moderated;

    if ($blog->email_attn_reqd_comments && !$attn_reqd) {
        return;
    }

    require MT::Mail;
    my $author = $entry->author;
    $app->set_language($author->preferred_language)
        if $author && $author->preferred_language;
    my $from_addr;
    my $reply_to;
    if ($app->{cfg}->EmailReplyTo) {
        $reply_to = $comment->email;
    } else {
        $from_addr = $comment->email;
    }
    $from_addr = undef if $from_addr && !is_valid_email($from_addr);
    $reply_to = undef if $reply_to && !is_valid_email($reply_to);

    my $author_email_original;
    if ($author && $author->email) {
        if ($author->email =~ /,/) {
            # Save original author email for post-facto reversion
            $author_email_original = $author->email;

            # Split, dedupe, test validity and rejoin
        	my %seen;
        	my @emails = split(/[,\s]+/, $author->email);
        	@emails = grep(! $seen{$_}++ && is_valid_email($_), @emails);
            my $author_email_new = join(', ', @emails);        
            $author->email($author_email_new);
        } else {
            is_valid_email($author->email) or author->email('');
        }
    }
    return unless $author && $author->email;
        
    if (!$from_addr) {
        $from_addr = $app->{cfg}->EmailAddressMain || $author->email;
    }
    my %head = ( To => $author->email,
                 $from_addr ? (From => $from_addr) : (),
                 $reply_to ? ('Reply-To' => $reply_to) : (),
                 Subject =>
                 '[' . $blog->name . '] ' .
                 $app->translate("New Comment Posted to '[_1]'",
                                 $entry->title)
               );
    my $charset = $app->{cfg}->MailEncoding || $app->{cfg}->PublishCharset;
    $head{'Content-Type'} = qq(text/plain; charset="$charset");
    my $base;
    { local $app->{is_admin} = 1;
      $base = $app->base . $app->mt_uri; }
    if ($base =~ m!^/!) {
        my ($blog_domain) = $blog->site_url =~ m|(.+://[^/]+)|;
        $base = $blog_domain . $base;
    }
    my %param = (
                 blog_name => $blog->name,
                 entry_id => $entry->id,
                 entry_title => $entry->title,
                 view_url => $comment_link,
                 edit_url => $base . $app->uri_params('mode' => 'view', args => { blog_id => $blog->id, '_type' => 'comment', id => $comment->id}),
                 ban_url => $base . $app->uri_params('mode' => 'save', args => {'_type' => 'banlist', blog_id => $blog->id, ip => $comment->ip}),
                 comment_ip => $comment->ip,
                 comment_name => $comment->author,
                 (is_valid_email($comment->email)?
                  (comment_email => $comment->email):()),
                 comment_url => $comment->url,
                 comment_text => $comment->text,
                 unapproved => !$comment->visible(),
                );
    require MT::I18N;
    my $body = MT->build_email('new-comment.tmpl', \%param);
    $body = MT::I18N::wrap_text($body, 72);

    $author->email($author_email_original) if $author_email_original;

    MT::Mail->send(\%head, $body)
        or return $app->handle_error(MT::Mail->errstr());
}

1;