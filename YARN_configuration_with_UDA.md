# Introduction #

UDA over YARN gives even better value comparing to the value of UDA over Hadoop-1.x.  Please notice that YARN requires different configuration than Hadoop-1 for loading UDA


# Details #


  * Please start with [Pluggable Shuffle in YARN configuration page](http://hadoop.apache.org/docs/current/hadoop-mapreduce-client/hadoop-mapreduce-client-core/PluggableShuffleAndPluggableSort.html).

  * Above page is missing one property (that was requested after the page was written), please add it too to your mapred-site.xml.
```
  <property>
    <name>mapreduce.job.shuffle.provider.services</name>
    <value>uda_shuffle</value>
    <description>A comma-separated list of classes that should be loaded as ShuffleProviderPlugin(s).
    A ShuffleProviderPlugin can serve shuffle requests from reducetasks.
    </description>
  </property>
```
  * We recommend taking latest UDA from [our Downloads page](https://code.google.com/p/uda-plugin/downloads/list) and referring to our [UDA\_Tuning\_Recommendations\_for\_Hadoop\_2](UDA_Tuning_Recommendations_for_Hadoop_2.md) .