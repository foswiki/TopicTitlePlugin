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

package Foswiki::Plugins::TopicTitlePlugin::Core;

use strict;
use warnings;

use Foswiki::Func    ();
use Foswiki::Plugins ();

use constant TRACE => 0;    # toggle me

sub new {
    my $class = shift;
    my $session = shift || $Foswiki::Plugins::SESSION;

    my $this = bless(
        {
            session   => $session,
            baseWeb   => $session->{webName},
            baseTopic => $session->{topicName},
            @_
        },
        $class
    );

    return $this;
}

sub finish {
    my $this = shift;

    undef $this->{cache};
    undef $this->{session};
}

sub TOPICTITLE {
    my ( $this, $params, $topic, $web ) = @_;

    my $theWeb = $params->{web} || $web;
    $theWeb =~ s/^\s+|\s+$//g;

    my $theTopic = $params->{_DEFAULT} || $params->{topic} || $topic;
    $theTopic =~ s/^\s+|\s+$//g;

    ( $theWeb, $theTopic ) =
      Foswiki::Func::normalizeWebTopicName( $theWeb, $theTopic );

    my $topicTitle = $this->getTopicTitle( $theWeb, $theTopic, $params->{rev} );

    my $theDefault = $params->{default};
    if ( $topicTitle eq $theTopic && defined($theDefault) ) {
        $topicTitle = $theDefault;
    }

    my $theHideAutoInc = Foswiki::Func::isTrue( $params->{hideautoinc}, 0 );
    return '' if $theHideAutoInc && $topicTitle =~ /X{10}|AUTOINC\d/;

    my $theEncoding = $params->{encode} || '';
    return _quoteEncode($topicTitle)          if $theEncoding eq 'quotes';
    return Foswiki::urlEncode($topicTitle)    if $theEncoding eq 'url';
    return Foswiki::entityEncode($topicTitle) if $theEncoding eq 'entity';

    return $topicTitle;
}

sub renderWikiWordHandler {
    my ( $this, $theLinkText, $hasExplicitLinkLabel, $theWeb, $theTopic ) = @_;

    return if $hasExplicitLinkLabel;

    _writeDebug( "called renderWikiWordHandler($theLinkText, "
          . ( $hasExplicitLinkLabel ? '1' : '0' )
          . ", $theWeb, $theTopic)" )
      if TRACE;

    return if !defined($theWeb) and !defined($theTopic);

    # normalize web name
    $theWeb =~ s/\//./g;
    my $topicTitle = $this->getTopicTitle( $theWeb, $theTopic );

    _writeDebug("topicTitle=$topicTitle")
      if TRACE;

    return unless defined($topicTitle) && $topicTitle ne $theLinkText;
    return $topicTitle;
}

sub afterRenameHandler {
    my ( $this, $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic,
        $newAttachment )
      = @_;

    _writeDebug(
"called afterRenameHandler(oldWeb=$oldWeb, oldTopic=$oldTopic, newWeb=$newWeb, newTopic=$newTopic)"
    ) if TRACE;

    # remember the base topic being renamed
    $this->{baseWeb}   = $newWeb;
    $this->{baseTopic} = $newTopic;
}

# This function will store the TopicTitle in a preference variable if it isn't
# part of the DataForm of this topic.
sub beforeSaveHandler {
    my ( $this, $text, $topic, $web, $meta ) = @_;

    _writeDebug("called beforeSaveHandler($web, $topic)") if TRACE;

    # only treat the base topic
    unless ( $web eq $this->{baseWeb} && $topic eq $this->{baseTopic} ) {
        _writeDebug(
            "... not saving the base $this->{baseWeb}.$this->{baseTopic}")
          if TRACE;
        return;
    }

    # find out if we received a TopicTitle
    my $request = Foswiki::Func::getCgiQuery();
    my $topicTitleField =
      $meta->getPreference("TOPICTITLE_FIELD") || "TopicTitle";

    my $topicTitle = $request->param($topicTitleField);
    unless ( defined $topicTitle ) {
        _writeDebug("didn't get a TopicTitle, nothing do here") if TRACE;
        return;
    }

    if ( $topicTitle =~ m/X{10}|AUTOINC\d/ ) {
        _writeDebug("ignoring topic being auto-generated") if TRACE;
        return;
    }

    my $fieldTopicTitle = $meta->get( 'FIELD', $topicTitleField );
    _writeDebug("topic=$web.$topic, topicTitle=$topicTitle") if TRACE;

    if ( $topicTitle eq $topic ) {
        _writeDebug("same as topic name ... nulling") if TRACE;
        $request->param( $topicTitleField, "" );
        $topicTitle = '';
        if ( defined $fieldTopicTitle ) {
            $fieldTopicTitle->{value} = "";
        }
    }

    # find out if this topic can store the TopicTitle in its metadata
    if ( defined $fieldTopicTitle ) {
        _writeDebug("storing it into the formfield") if TRACE;

        # however, check if we've got a TOPICTITLE preference setting
        # if so remove it. this happens if we stored a topic title but
        # then added a form that now takes the topic title instead
        if ( defined $meta->get( 'PREFERENCE', 'TOPICTITLE' ) ) {
            _writeDebug("removing redundant TopicTitles in preferences")
              if TRACE;
            $meta->remove( 'PREFERENCE', 'TOPICTITLE' );
        }

        $fieldTopicTitle->{value} = $topicTitle;
        return;
    }

    _writeDebug("we need to store the TopicTitle in the preferences") if TRACE;

    # if it is a topic setting, override it.
    my $topicTitleHash = $meta->get( 'PREFERENCE', 'TOPICTITLE' );
    if ( defined $topicTitleHash ) {
        _writeDebug(
"found old TopicTitle in preference settings: $topicTitleHash->{value}"
        ) if TRACE;
        if ($topicTitle) {

            # set the new value
            $topicTitleHash->{value} = $topicTitle;
        }
        else {

            # remove the value if the new TopicTitle is an empty string
            $meta->remove( 'PREFERENCE', 'TOPICTITLE' );
        }
        return;
    }

    _writeDebug("no TopicTitle in preference settings") if TRACE;

    # if it is a bullet setting, replace it.
    if ( $text =~
s/((?:^|[\n\r])(?:\t|   )+\*\s+(?:Set|Local)\s+TOPICTITLE\s*=\s*)(.*)((?:$|[\r\n]))/$1$topicTitle$3/
      )
    {
        _writeDebug("found old TopicTitle defined as a bullet setting: $2")
          if TRACE;
        $_[0] = $text;
        return;
    }

    _writeDebug(
        "no TopicTitle stored anywhere. creating a new preference setting")
      if TRACE;

    if ($topicTitle) {    # but only if we don't set it to the empty string
        $meta->putKeyed(
            'PREFERENCE',
            {
                name  => 'TOPICTITLE',
                title => 'TOPICTITLE',
                type  => 'Local',
                value => $topicTitle
            }
        );
    }
}

sub getTopicTitle {
    my ( $this, $web, $topic, $rev, $meta ) = @_;

    _writeDebug( "called getTopicTitle($web, "
          . ( $topic // 'undef' ) . ", "
          . ( $rev   // 'undef' ) . ", "
          . ( $meta  // 'undef' )
          . ")" )
      if TRACE;

    $topic ||= $Foswiki::cfg{HomeTopicName};
    my $key = $web . "::" . $topic . "::" . ( $rev // "0" );
    my $topicTitle = $this->{cache}{$key};
    if ( defined $topicTitle ) {
        _writeDebug(
            "... found topicTitle for $key in cache (web='$web', topic='$topic'"
        ) if TRACE;
        return $topicTitle;
    }

    ($meta) = Foswiki::Func::readTopic( $web, $topic, $rev )
      unless defined $meta;

    if ( $Foswiki::cfg{SecureTopicTitles} ) {
        my $wikiName = Foswiki::Func::getWikiName();
        return $topic
          unless Foswiki::Func::checkAccessPermission( 'VIEW', $wikiName,
            undef, $topic, $web, $meta );
    }

    my $topicTitleField =
      $meta->getPreference("TOPICTITLE_FIELD") || "TopicTitle";
    _writeDebug("topicTitleField=$topicTitleField")
      if TRACE;

    # read the formfield value
    $topicTitle = $meta->get( 'FIELD', $topicTitleField );
    $topicTitle = $topicTitle->{value} if $topicTitle;

    _writeDebug("found topicTitle in formfield: $topicTitle")
      if TRACE && $topicTitle;

    # read the preference
    unless ($topicTitle) {
        $topicTitle = $meta->getPreference('TOPICTITLE');
        _writeDebug("found topicTitle in preference: $topicTitle")
          if TRACE && $topicTitle;
    }

    # read the local preference
    unless ($topicTitle) {
        $topicTitle = $meta->get( 'PREFERENCE', 'TOPICTITLE' );
        $topicTitle = $topicTitle->{value} if $topicTitle;
        _writeDebug("found topicTitle in local preference: $topicTitle")
          if TRACE && $topicTitle;
    }

    # default to topic name
    $topicTitle = $topic unless $topicTitle;

    $topicTitle =~ s/^\s+|\s+$//g;
    $topicTitle =~ s/<!--.*?-->//g;

    # if it is WebHome, make it the web's base name
    if ( $topicTitle eq $Foswiki::cfg{HomeTopicName} ) {
        $topicTitle = $web;
        $topicTitle =~ s/^.*[\.\/]//;
        _writeDebug("topicTitle is a webTitle: $topicTitle")
          if TRACE && $topicTitle;
    }

    _writeDebug("finally, topicTitle=$topicTitle") if TRACE;

    $this->{cache}{$key} = $topicTitle;
    return $topicTitle;
}

sub _writeDebug {

    #Foswiki::Func::writeDebug("TopicTitlePlugin::Core - $_[0]");
    print STDERR "TopicTitlePlugin::Core - $_[0]\n";
}

sub _quoteEncode {
    my $text = shift;

    $text =~ s/\"/\\"/g;

    return $text;
}

1;
