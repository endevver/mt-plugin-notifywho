# NotifyWho?! plugin #
Version:    1.03
Author:     Jay Allen
Date:       January 18th, 2006
Home:       http://jayallen.org/projects/notifywho

## INTRODUCTION ##

The NotifyWho?! plugin enables you to control exactly who should receive
comment and TrackBack notifications for each blog.

You can configure the plugin to send them to:

    * The Entry author (MT default)
    * One or more arbitrary email addresses
    * Both of the above

## Requirements ##

    * Movable Type 3.2 or higher or Movable Type Enterprise
    * A working email notification system
    * Ability to install plugins
    * Permission to configure a blog and its plugins


## INSTALLATION ##

Unpack the plugin archive and upload the entire notifywho folder to the
plugins folder in your MT directory. The files installed and their locations
should match that shown below:

    MT_DIR/
            plugins/
                    NotifyWho/
                              lib/
                                  NotifyWho.pm
                                  NotifyWho/
                                            L10N/
                                                 en_us.pm
                              notifywho.pl
                              tmpl/
                                   blog_config.tmpl

All files should have permissions which make them readable by the web 
server (chmod 644 or rw-r--r--). You don't have to worry about this unless 
your FTP software modifies or fails to mirror the permissions upon upload 
without asking. (Pssst! Time to get new FTP software...)


## AND THE REST IS, AS THEY SAY, BLOGGED ##

For configuration and usage instructions, bug reports, feature requests or 
general feedback, see the NotifyWho?! blog.

    http://jayallen.org/projects/notifywho

