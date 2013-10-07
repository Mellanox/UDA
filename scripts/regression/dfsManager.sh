# Written by Elad Itzhakian 06/08/13

PREFIX="$(basename $0):"

concatWildcard()
{
	WITH_WILDCARD=""
	ARG="$*"
	if [[ "$ARG" != 0 ]]; then
		for z in $ARG;
		do
			NEWARG="$z/*"
			WITH_WILDCARD="$WITH_WILDCARD $NEWARG"
		done
	else
		echo "$PREFIX Fatal error: given null directory. exiting!"
		exit 5
	fi
}

deletePartitions()
{
	dirsToDelete="$1"
	machines=$2
	concatWildcard $dirsToDelete
	echo "$PREFIX Formatting $dirsToDelete on $machines"
	echo "sudo pdsh -w $machines rm -rf $WITH_WILDCARD"
	sudo pdsh -w $machines "rm -rf $WITH_WILDCARD"
}

formatNamenode()
{
	echo "$PREFIX Formatting namenode"
	echo "$MY_HADOOP_HOME/$DFS_FORMAT 2>&1"
	$MY_HADOOP_HOME/$DFS_FORMAT 2>&1
	if [[ "$?" != 0 ]]; then
		echo "$PREFIX ERROR: Namenode format failed."
		exit 5
	fi
}

setPermissions()
{
	dirsToSet="$1"
	machines=$2
	echo "$PREFIX setting permissions of $DFS_PERMISSIONS in $dirsToSet on $machines"
	echo "sudo pdsh -w $machines chmod -R $DFS_PERMISSIONS $dirsToSet"
	sudo pdsh -w $machines "chmod -R $DFS_PERMISSIONS $dirsToSet"
	echo "sudo pdsh -w $machines chown -R $USER $dirsToSet"
	sudo pdsh -w $machines "chown -R $USER $dirsToSet"
}

managePartitionsDeletion()
{
	deletePartitions "$MASTER_DFS_DIRS_BY_SPACES" "$MASTER"
	deletePartitions "$SLAVES_DFS_DIRS_BY_SPACES" "$ALL_SLAVES_BY_COMMAS"
}

managePartitionsPermissions()
{
	setPermissions "$MASTER_DFS_DIRS_BY_SPACES" "$MASTER"
	setPermissions "$SLAVES_DFS_DIRS_BY_SPACES" "$ALL_SLAVES_BY_COMMAS"
}

restartDfs()
{
	managePartitionsDeletion	
	formatNamenode
	echo "$PREFIX Format successfully completed."
	echo "$PREFIX (Formerly known as GREAT FORMAT ALL DISKS FORMATTED !!!)"
}

#if [ -z "$ENV_MACHINES_BY_COMMAS" ] ; then
#	echo "$PREFIX Fatal error: ENV_MACHINES_BY_COMMAS variable is unset. Exiting!"
#	exit 5
#fi

<<COMM
generalDirs="$HADOOP_TMP_DIR_BY_SPACES"
yarnDirs="$DFS_DATANODE_DATA_DIR_BY_SPACES $DFS_NAMENODE_NAME_DIR_BY_SPACES $MAPREDUCE_CLUSTER_LOCAL_DIR_BY_SPACES $YARN_NODEMANAGER_LOGDIRS_BY_SPACES $YARN_NODEMANAGER_LOCALDIRS_BY_SPACES"
hadoop1Dirs="$DFS_DATA_DIR_BY_SPACES $DFS_NAME_DIR_BY_SPACES $MAPRED_LOCAL_DIR_BY_SPACES"
generalDirs="$ALL_DFS_DIRS_BY_SPACES"
alldirs="$generalDirs"
if (($YARN_HADOOP_FLAG == 1));then
	alldirs="$alldirs $yarnDirs"
else
	alldirs="$alldirs $hadoop1Dirs"
fi
COMM

while getopts ":fdpr" Option
do
	case ${Option} in
		"f"     ) formatNamenode ;;
		"d"     ) managePartitionsDeletion ;; 
		"p"     ) managePartitionsPermissions ;; 
		"r"     ) restartDfs ;;
		*     	) echo "$echoPrefix: wrong input" ;  exit $SEC ;;   # Default.
	esac
done

exit 0