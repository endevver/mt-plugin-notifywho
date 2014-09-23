# Introduction

The NotifyWho?! plugin enables you to control exactly who should receive
entry, comment and TrackBack notifications for each blog.

You can configure the plugin to send any combination of:

   * Entry creation and publication notifications:
       * Author (useful when entries added on behalf of author, such as via [Ghostwriter](https://plugins.movabletype.org/ghostwriter/))
       * Arbitrary email addresses
       * The blog’s [address book](https://movabletype.org/documentation/appendices/config-directives/enableaddressbook.html) (i.e. notification list)
   * Feedback notifications:
       * Author (Movable Type default)
       * Arbitrary email addresses
       * The blog’s [address book](https://movabletype.org/documentation/appendices/config-directives/enableaddressbook.html)

For entry notifications, you can configure the plugin to send them
automatically or to simply provide defaults for the Share entry screen.
Automatic notifications can be disabled on a per entry basis by toggling the
link directly about the entry save/preview buttons.

# Requirements

* Movable Type 4+
* A working email notification system
* Ability to install plugins
* Permission to configure a blog and its plugins

# Installation

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install

# Configuration

NotifyWho can be configured at the blog level by visiting Tools > Plugins > NotifyWho > Settings. There are two areas to configure notifications for: entry and feedback. As noted above, NotifyWho can be configured to send email to the Entry author, arbitrary email addresses, the blog's address book, or any of the above.

Notifications can be sent when an entry is created, and when an entry is published. These are both options specifically for blogs that are set to *not* publish by default, where being notified that an entry has been created could be useful.

# Public submissions

If you're making use of the Community.Pack's public submission form capability, it is likely useful to receive an email when the new entry is created or published. NotifyWho can work with the public submission form with a simple addition to the form:

    <input type="hidden" name="auto_notifications" value="1" />

# Known issues

NotifyWho uses Movable Type’s built in `send_notify` function, which always sends a notification to the entry author in addition to any other recipients. It is therefore not currently possible to exclude the author from the recipients list. If you want to *only* notify the author, though, the plugin must explicitly send a notifcation to the author, but this results in two e-mails being sent to the author since the `send_notify` always sends an e-mail to the author in addition to the given recipients. If you are sending notifications to anyone aside from the author, then you can uncheck the “Author” option in the plugin settings, since the author will be notified anyway. This will avoid duplicate e-mails being sent to the author.

# Copyright

Copyright 2009-2012, [Endevver LLC](http://endevver.com). All rights reserved.
