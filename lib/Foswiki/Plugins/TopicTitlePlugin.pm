# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# TopicTitlePlugin is Copyright (C) 2018 Foswiki Contributors https://foswiki.org
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::TopicTitlePlugin;

use strict;
use warnings;

use Foswiki::Func ();

our $VERSION           = '1.01';
our $RELEASE           = '28 May 2018';
our $SHORTDESCRIPTION  = 'Free-form title for topics';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

# monkey-patch Func API
BEGIN {
    if ( $Foswiki::cfg{Plugins}{TopicTitlePlugin}{Enabled}
        && !defined(&Foswiki::Func::getTopicTitle) )
    {
        no warnings 'redefine';
        *Foswiki::Func::getTopicTitle =
          \&Foswiki::Plugins::TopicTitlePlugin::getTopicTitle;
        use warnings 'redefine';
    }
    else {
        #print STDERR "suppressing monkey patching via TopicTitlePlugin\n";
    }
}

sub initPlugin {

    Foswiki::Func::registerTagHandler( 'TOPICTITLE',
        sub { return getCore()->TOPICTITLE(@_); } );

    # alias
    Foswiki::Func::registerTagHandler( 'GETTOPICTITLE',
        sub { return getCore()->TOPICTITLE(@_); } );

    # indicate feature
    Foswiki::Func::getContext()->{TopicTitleEnabled} = 1;

    return 1;
}

sub renderWikiWordHandler {
    return getCore()->renderWikiWordHandler(@_);
}

sub beforeSaveHandler {
    return getCore()->beforeSaveHandler(@_);
}

sub getTopicTitle {
    return getCore()->getTopicTitle(@_);
}

sub getCore {
    unless ( defined $core ) {
        require Foswiki::Plugins::TopicTitlePlugin::Core;
        $core = Foswiki::Plugins::TopicTitlePlugin::Core->new();
    }
    return $core;
}

sub finishPlugin {
    if ( defined $core ) {
        $core->finish();
        undef $core;
    }
}

1;
