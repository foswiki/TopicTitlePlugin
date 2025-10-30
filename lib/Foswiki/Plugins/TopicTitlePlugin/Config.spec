# ---+ Extensions
# ---++ TopicTitlePlugin

# **BOOLEAN*
# When enabled links to topics in other webs will still display the webname
$Foswiki::cfg{TopicTitlePlugin}{LegacyWikiWords} = 0;

# **BOOLEAN**
# When enabling this option, reading TopicTitles is protected by view rights on that topic.
# Note, however, that this might cause a performance degradation as every wiki link will
# require a permission check.
$Foswiki::cfg{TopicTitlePlugin}{SecureTopicTitles} = 0;


1;
