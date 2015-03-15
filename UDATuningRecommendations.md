# UDA Tuning Recommendations for Hadoop-1 (UDA-3.1.11-0) #

### System tuning ###
| _swapoff –a_ |  Disable swap on all devices (verify with 'swapon -s') |
|:---------------|:-------------------------------------------------------|
| _echo 1 > /proc/sys/vm/overcommit\_memory_ | Allow overcommit of memory for processes forking |

### Hadoop tuning ###
| **File** | **Parameter** | **Value** | **Comment** |
|:---------|:--------------|:----------|:------------|
| conf/hdfs-site.xml | dfs.block.size | 512 MB | Use large HDFS block size |
| conf/mapred-site.xml | mapred.tasktracker.map.tasks.maximum | 16 | The maximum number of map tasks that will be run simultaneously by a task tracker.|
| conf/mapred-site.xml | mapred.tasktracker.reduce.tasks.maximum | 4 | The maximum number of reduce tasks that will be run simultaneously by a task tracker.|

### Job tuning ###
| **Command Line Parameter and Valua** | **Comment** |
|:-------------------------------------|:------------|
| _-Dio.sort.mb=600_ | Allow map task to sort without spilling with |
| _-Dmapred.map.tasks.speculative.execution=false_ _-Dmapred.reduce.tasks.speculative.execution=false_ | Disable speculative execution which is not supported yet by UDA |
| _-Dmapred.reduce.slowstart.completed.maps=0.95_ | UDA start shuffle only after all map tasks are done, postpone reduce tasks launching as much as possible |
| _-Dmapred.map.child.java.opts=-Xmx1000m_ | Provide more memory for map task JVM |
| _-Dmapred.reduce.child.java.opts=-Xmx2000m_ | Provide more memory for reduce task JVM. This should take into consideration the number of map tasks `*` the required RDMA buffer size. |
| _-Dio.sort.record.percent=0.138_ | The percentage of io.sort.mb dedicated to tracking record boundaries. |
| _-Dio.sort.spill.percent=1_ | The soft limit in either the buffer or record collection buffers. Once reached, a thread will begin to spill the contents to disk in the background. |