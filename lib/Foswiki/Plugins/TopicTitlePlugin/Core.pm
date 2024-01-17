# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# TopicTitlePlugin is Copyright (C) 2018-2024 Foswiki Contributors https://foswiki.org
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

use Foswiki::Func ();
use Foswiki::Plugins ();

use constant TRACE => 0;    # toggle me

sub new {
  my $class = shift;
  my $session = shift || $Foswiki::Plugins::SESSION;

  my $this = bless({
      session => $session,
      baseWeb => $session->{webName},
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
  my ($this, $params, $topic, $web) = @_;

  #_writeDebug("called TOPICTITLE");

  my $theWeb = $params->{web} || $web;
  $theWeb =~ s/^\s+|\s+$//g;

  my $theTopic = $params->{_DEFAULT} || $params->{topic} || $topic;
  $theTopic =~ s/^\s+|\s+$//g;

  #_writeDebug("theTopic=$theTopic");

  my $request = Foswiki::Func::getCgiQuery();
  my $rev = $params->{rev} || $request->param("rev");
  my $topicTitle = $this->getTopicTitle($theWeb, $theTopic, $rev);
  #_writeDebug("topicTitle=$topicTitle");

  my $theDefault = $params->{default};
  if ($topicTitle eq $theTopic && defined($theDefault)) {
    $topicTitle = $theDefault;
  }

  my $theHideAutoInc = Foswiki::Func::isTrue($params->{hideautoinc}, 0);
  return '' if $theHideAutoInc && $topicTitle =~ /X{10}|AUTOINC\d/;

  my $theEncoding = $params->{encode} || '';
  return _quoteEncode($topicTitle) if $theEncoding eq 'quotes';
  return Foswiki::urlEncode($topicTitle) if $theEncoding eq 'url';
  return Foswiki::entityEncode($topicTitle) if $theEncoding eq 'entity';
  return _safeEncode($topicTitle) if $theEncoding eq 'safe';

  return $topicTitle;
}

sub renderWikiWordHandler {
  my ($this, $theLinkText, $hasExplicitLinkLabel, $theWeb, $theTopic) = @_;

  return if $hasExplicitLinkLabel;

  #_writeDebug("called renderWikiWordHandler($theLinkText, " . ($hasExplicitLinkLabel ? '1' : '0') . ", $theWeb, $theTopic)");

  return if !defined($theWeb) && !defined($theTopic);

  # normalize web name
  $theWeb =~ s/\//./g;
  my $topicTitle = $this->getTopicTitle($theWeb, $theTopic);

  #_writeDebug("topicTitle=$topicTitle");

  return unless defined($topicTitle) && $topicTitle ne $theLinkText;
  return $topicTitle;
}

sub afterRenameHandler {
  my ($this, $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

  _writeDebug("called afterRenameHandler(oldWeb=$oldWeb, oldTopic=$oldTopic, newWeb=$newWeb, newTopic=$newTopic)");

  # remember the base topic being renamed
  $this->{baseWeb} = $newWeb;
  $this->{baseTopic} = $newTopic;
}

# This function will store the TopicTitle in a preference variable if it isn't
# part of the DataForm of this topic.
sub beforeSaveHandler {
  my ($this, $text, $topic, $web, $meta) = @_;

  _writeDebug("called beforeSaveHandler($web, $topic)");

  # clearing cache
  undef $this->{cache};

  # only treat the base topic
  unless ($web eq $this->{baseWeb} && $topic eq $this->{baseTopic}) {
    _writeDebug("... not saving the base $this->{baseWeb}.$this->{baseTopic}");
    return;
  }

  # find out if we received a TopicTitle
  my $request = Foswiki::Func::getRequestObject();
  my $fieldName = $meta->getPreference("TOPICTITLE_FIELD") || "TopicTitle";

  my $topicTitle = $request->param($fieldName);
  return unless defined $topicTitle;

  _writeDebug("topic=$web.$topic, topicTitle=$topicTitle");

  if ($topicTitle =~ m/X{10}|AUTOINC\d/) {
    _writeDebug("ignoring topic being auto-generated");
    return;
  }

  if ($topic eq $Foswiki::cfg{HomeTopicName}) {
    my $baseName = $web;
    $baseName =~ s/^.*[\/\.]//;
    if ($topicTitle eq $web || $topicTitle eq $baseName) {
      _writeDebug("same as web name ... nulling");
      $request->param($fieldName, "");
      $topicTitle = '';
    }
  } else {
    if ($topicTitle eq $topic) {
      _writeDebug("same as topic name ... nulling");
      $request->param($fieldName, "");
      $topicTitle = '';
    }
  }

  $this->setTopicTitle($web, $topic, $topicTitle, $meta, 1);
}

sub setTopicTitle {
  my ($this, $web, $topic, $title, $meta, $dontSave) = @_;

  $title //= $topic;

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);
  _writeDebug("called setTopicTitle(web=$web, topic=" . ($topic // 'undef').", title=$title)");

  ($meta) = Foswiki::Func::readTopic($web, $topic) unless defined $meta;

  my $wikiName = Foswiki::Func::getWikiName();
  return unless Foswiki::Func::checkAccessPermission('VIEW', $wikiName, undef, $topic, $web, $meta);

  my $lang = uc($this->{session}->i18n->language() || 'en');

  my $fieldName = $meta->getPreference("TOPICTITLE_FIELD") || "TopicTitle";
  _writeDebug("fieldName=$fieldName");

  my $mustSave = 0;

  # read the formfield 
  my $field = $meta->get('FIELD', $fieldName . $lang);
  $field //= $meta->get('FIELD', $fieldName);

  if ($field) {
    _writeDebug("saving topicTitle in formfield");

    # check if we've got a TOPICTITLE preference setting
    # if so remove it. this happens if we stored a topic title but
    # then added a form that now takes the topic title instead

    if (defined $meta->get('PREFERENCE', 'TOPICTITLE')) {
      _writeDebug("removing redundant TopicTitles in preferences");
      $meta->remove('PREFERENCE', 'TOPICTITLE');
      $mustSave = 1;
    }

    if ($field->{value} ne $title) {
      $field->{value} = $title;

      $meta->putKeyed("FIELD", $field);
      $mustSave = 1;
    }

  }  else {

    # read the local preference

    my $prefName = "TOPICTITLE_$lang";
    $field = $meta->get('PREFERENCE', $prefName);

    unless (defined $field) {
      $prefName = "TOPICTITLE";
      $field //= $meta->get('PREFERENCE', $prefName);
    }

    unless (defined $field) {
      $prefName = "TOPICTITLE";
      $field = {
        name => $prefName,
        title => $prefName,
        type => "Local",
        value => "",
      };
    }
    _writeDebug("prefName=$prefName");

    my $baseName = $web;
    $baseName =~ s/^.*[\/\.]//;

    if ($title eq $topic || ($topic eq $Foswiki::cfg{HomeTopicName} && ($title eq $web || $title eq $baseName))) {
      _writeDebug("removing topicTitle preference");
      $meta->remove("PREFERENCE", $prefName);;
      $mustSave = 1;
    } else {
      _writeDebug("saving topicTitle in preference");
      if ($field->{value} ne $title) {
        $field->{value} = $title;
        $meta->putKeyed("PREFERENCE", $field);
        $mustSave = 1;
      } else {
        _writeDebug("... value didn't change");
      }
    }
  }

#   # if it is a bullet setting, replace it.
#   if ($text =~ s/((?:^|[\n\r])(?:\t|   )+\*\s+(?:Set|Local)\s+TOPICTITLE\s*=\s*)(.*)((?:$|[\r\n]))/$1$topicTitle$3/) {
#     _writeDebug("found old TopicTitle defined as a bullet setting: $2");
#     $_[0] = $text;
#     return;
#   }

  my $rev;
  (undef, undef, $rev) = $meta->getRevisionInfo();
  #_writeDebug("rev=$rev");

  my $key = $web . "::" . $topic . "::" . ($rev // "0");
  #_writeDebug("key=$key");
  $this->{cache}{$key} = $title;

  $meta->saveAs() if !$dontSave && $mustSave;
}

sub getTopicTitle {
  my ($this, $web, $topic, $rev, $meta) = @_;

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  _writeDebug("called getTopicTitle($web, " . ($topic // 'undef') . ", " . ($rev // 'undef') . ", " . ($meta // 'undef') . ")");

  $topic ||= $Foswiki::cfg{HomeTopicName};
  my $key = $web . "::" . $topic . "::" . ($rev // "0");
  my $topicTitle = $this->{cache}{$key};
  if (defined $topicTitle) {
    _writeDebug("... found topicTitle for $key in cache (web='$web', topic='$topic'");
    return $topicTitle;
  }

  ($meta) = Foswiki::Func::readTopic($web, $topic, $rev) unless defined $meta;

  #_writeDebug("meta: ".$meta->stringify);

  if ($Foswiki::cfg{SecureTopicTitles}) {
    my $wikiName = Foswiki::Func::getWikiName();
    return $topic
      unless Foswiki::Func::checkAccessPermission('VIEW', $wikiName, undef, $topic, $web, $meta);
  }

  my $lang = uc($this->{session}->i18n->language() || 'en');

  my $fieldName = $meta->getPreference("TOPICTITLE_FIELD") || "TopicTitle";
  _writeDebug("fieldName=$fieldName");

  # read the formfield value
  $topicTitle = $meta->get('FIELD', $fieldName . $lang);
  $topicTitle //= $meta->get('FIELD', $fieldName);
  $topicTitle = $topicTitle->{value} if $topicTitle;

  _writeDebug("found topicTitle in formfield: $topicTitle") if $topicTitle;

  # read the preference
  unless ($topicTitle) {
    $topicTitle = $meta->getPreference('TOPICTITLE_' . $lang);
    $topicTitle //= $meta->getPreference('TOPICTITLE');
    _writeDebug("found topicTitle in preference: $topicTitle") if $topicTitle;
  }

  # read the local preference
  unless ($topicTitle) {
    $topicTitle = $meta->get('PREFERENCE', 'TOPICTITLE_' . $lang);
    $topicTitle //= $meta->get('PREFERENCE', 'TOPICTITLE');
    $topicTitle = $topicTitle->{value} if $topicTitle;
    _writeDebug("found topicTitle in local preference: $topicTitle") if $topicTitle;
  }

  # default to topic name
  $topicTitle ||= $topic;

  $topicTitle =~ s/^\s+|\s+$//g;
  $topicTitle =~ s/<!--.*?-->//g;

  # if it is WebHome, make it the web's base name
  if ($topicTitle eq $Foswiki::cfg{HomeTopicName}) {
    $topicTitle = $web;
    $topicTitle =~ s/^.*[\.\/]//;
    _writeDebug("topicTitle is a webTitle: $topicTitle") if $topicTitle;
  }

  _writeDebug("finally, topicTitle=$topicTitle");

  $this->{cache}{$key} = $topicTitle;
  return $topicTitle;
}

sub _writeDebug {

  #Foswiki::Func::writeDebug("TopicTitlePlugin::Core - $_[0]");
  print STDERR "TopicTitlePlugin::Core - $_[0]\n" if TRACE;
}

sub _quoteEncode {
  my $text = shift;

  $text =~ s/\"/\\"/g;

  return $text;
}

sub _safeEncode {
  my $text = shift;

  $text =~ s/([<>%'"])/'&#'.ord($1).';'/ge;
  return $text;
}

1;
