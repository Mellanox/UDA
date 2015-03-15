# UDA Tuning Recommendations for Hadoop-2 #

### System tuning ###

**For tuning UDA:**
  1. For UDA with Hadoop-2 (YARN), the most important thing is to configure **slowstart=100%** (mapreduce.job.reduce.slowstart.completedmaps=1.00) and giving all the map/reduce resources (RAM/CPU) to mappers at map phase, and giving all the map/reduce resources to reducers at reduce phase.  This is because anyhow, UDA’s levitated merge causes reducers to wait till all mappers completes.  Hence, no need to give reducers resources while mappers are running and vice versa.
  1. If memory is limited (usually this is the case :-) ), we’ll be able to save memory and perform better with bigger HDFS splits (**dfs.block.size**).  Usually, I configure 512MB in this field.
  1. Last thing, Reducers in UDA like to have a lot of memory.  This is because we want to work in RAM and not on DISK. Hence, usually it is better for UDA to **configure less reducers and give more memory for each reducer**.  In most systems 2-4 reducers (per machine) are enough with UDA

**IPoIB and general tuning:**
  1. We don’t have special requirement for IP over IB.
  1. We have one general recommendation for all systems – to **remove swap partition from the system**.  This is because Linux starts using swap when RAM usage reaches ~50% load.  However, if your Hadoop will use swap than expect severe performance degradation.  Hence, we recommend removing swap partitions from all machines to allow using 100% of your RAM without swap.

**See also:**

[YARN\_configuration\_with\_UDA](YARN_configuration_with_UDA.md)