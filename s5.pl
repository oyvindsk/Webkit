#!/usr/bin/env perl

=head1 NAME

s5.pl - Convert an S5 presentation to PDF

=head1 SYNOPSIS

s5.pl [OPTION]... [URI [FILE]]

    -w WIDTH,  --width WIDHT    the width of the slides in pixels
    -h HEIGHT, --height HEIGHT  the height of the slides in pixels
    -S,        --no-steps       rendender only full slides (skip the steps)
    -h, --help                  print this help message

Simple usage:

    s5.pl --type svg s5-presentation.html

=head1 DESCRIPTION

Convert and s5 presentation into a PDF.

=cut

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long qw(:config auto_help);
use Pod::Usage;
use URI;

use Glib::Object::Introspection;
Glib::Object::Introspection->setup(
  basename => 'Gtk',
  version  => '3.0',
  package  => 'Gtk3'
);

Glib::Object::Introspection->setup(
  basename => 'WebKit',
  version  => '3.0',
  package  => 'WebKit'
);
use Cairo::GObject;
use Glib ':constants';


sub main {
    Gtk3::init(0, []);

    my $do_steps = 1;
    GetOptions(
        'w|width=i'  => \my $width,
        'h|height=i' => \my $height,
        'steps!'     => \$do_steps,
    ) or pod2usage(1);
    my ($uri, $filename) = @ARGV or pod2usage(1);
    $uri = "file://$uri" if -e $uri;
    $filename ||= "s5.pdf";


    my $view = WebKit::WebView->new();

    # Introduce some JavaScript helper methods. This methods will communicate
    # with the Perl script by writting data to the consolse.
    $view->execute_script(qq{
        function _is_end_of_slides () {
            var last_slide = (snum == smax - 1) ? true : false;
            var last_subslide = ( !incrementals[snum] || incpos >= incrementals[snum].length ) ? true : false;
            var ret = (last_slide && last_subslide) ? true : false ;
            // Let know Perl if we're done with the slides
            console.log("s5-end-of-slides: " + ret);
            return ret;
        }

        function _next_slide () {
            if ($do_steps && incrementals[snum] && incpos < incrementals[snum].length) {
                subgo(1);
            }
            else {
                go(1);
            }

            _is_end_of_slides();
        }

    });


    # Start taking screenshot as soon as the document is loaded. Maybe we want
    # to add an onload callback and to log a message once we're ready. We want
    # to take a screenshot only when the page is done being rendered.
    my $surface;
    $view->signal_connect('notify::load-status' => sub {
        return unless $view->get_uri and ($view->get_load_status eq 'finished');

        # We take a screenshot now
        # Sometimes the program dies with:
        #  (<unknown>:19092): Gtk-CRITICAL **: gtk_widget_draw: assertion `!widget->priv->alloc_needed' failed
        # This seem to happend is there's a newtwork error and we can't download
        # external stuff (e.g. facebook iframe). This timeout seems to help a bit.
        Glib::Idle->add(sub {
            $view->execute_script('_is_end_of_slides();');
        });
    });
    $view->load_uri($uri);


    # The JavaScripts communicates with Perl by writting into the console. This
    # is a hack but this is the best way that I could find so far.
    $view->signal_connect('console-message' => sub {
        my ($widget, $message, $line, $source_id) = @_;
        #print "CONSOLE $message at $line $source_id\n";
        my ($end) = ( $message =~ /^s5-end-of-slides: (true|false)$/) or return TRUE;

        # See if we need to create a new PDF or a new page
        if ($surface) {
            $surface->show_page();
        }
        else {
            my ($width, $height) = ($view->get_allocated_width, $view->get_allocated_height);
            $surface = Cairo::PdfSurface->create($filename, $width, $height);
        }

        # A new slide has been rendered on screen, we save it to the pdf
        my $cr = Cairo::Context->create($surface);
        $view->draw($cr);

        # Go to the next slide or stop grabbing screenshots
        if ($end eq 'true') {
            # No more slides to grab
            Gtk3->main_quit();
        }
        else {
            # Go on with the slide
            $view->execute_script('_next_slide();');
        }

        return TRUE;
    });

    my $window = Gtk3::OffscreenWindow->new();
    $window->set_default_size($width || 800, $height || 400);
    $window->add($view);
    $window->show_all();

    Gtk3->main();
    return 0;
}


exit main() unless caller;
