# ---+ Security and Authentication
# ---++ Access Control
# **BOOLEAN EXPERT**
# When enabling this option, reading TopicTitles is protected by view rights on that topic.
# Note, however, that this might cause a performance degradation as every wiki link will
# require a permission check.
$Foswiki::cfg{SecureTopicTitles} = 0;

1;
