# Written by Elad Itzhakian 06/08/13

echoPrefix=`eval $ECHO_PATTERN`

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
		echo "$echoPrefix: Fatal error: given null directory. exiting!"
		exit 5
	fi
}

deletePartitions()
{
	dirsToDelete="$1"
	machines=$2
	concatWildcard $dirsToDelete
	echo "$echoPrefix: Formatting $dirsToDelete on $machines"
	echo "sudo pdsh -w $machines rm -rf $WITH_WILDCARD"
	sudo pdsh -w $machines "rm -rf $WITH_WILDCARD"
}

formatNamenode()
{
	echo "$echoPrefix: Formatting namenode"
	echo "$MY_HADOOP_HOME/$DFS_FORMAT 2>&1"
	$MY_HADOOP_HOME/$DFS_FORMAT 2>&1
	if [[ "$?" != 0 ]]; then
		echo "$echoPrefix: ERROR: Namenode format failed."
		exit 5
	fi
}

setPermissions()
{
	dirsToSet="$1"
	machines=$2
	echo "$echoPrefix: setting permissions of $DFS_PERMISSIONS in $dirsToSet on $machines"
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
	echo "$echoPrefix: Format successfully completed."
	echo "$echoPrefix: (Formerly known as GREAT FORMAT ALL DISKS FORMATTED !!!)"
}

if (($SOFT_MODE_FLAG==1));then
	echo "$echoPrefix: running in soft-mode; $(basename $0) is deprecated"
	exit $CEC # exit and continue, for case someone will call this script from autoTester.sh
fi

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