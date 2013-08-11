# Written by Elad Itzhakian 06/08/13

source $SCRIPTS_DIR/exports.sh

PREFIX="$(basename $0):"

concatWildcard()
{
	WITH_WILDCARD=""
	ARG="$*"
	if [[ "$ARG" != 0 ]]; then
		for z in $ARG;
		do
			NEWARG="$z/\*"
			WITH_WILDCARD="$WITH_WILDCARD $NEWARG"
		done
	fi
}

formatDirOnSlaves()
{
	DIR="$*"
	if [[ "$DIR" != 0 ]]; then
	        concatWildcard $DIR
		echo "$PREFIX Formatting $DIR on all slaves"
        	echo "pdsh -w $SLAVES_BY_COMMAS rm -rf $WITH_WILDCARD"
	fi

}

formatDirOnMaster()
{
	DIR="$*"
	if [[ "$DIR" != 0 ]]; then
                concatWildcard $DIR
                echo "$PREFIX Formatting $DIR on master"
                echo "rm -rf $WITH_WILDCARD"
        fi
}

formatNamenode()
{
	echo "$PREFIX Formatting namenode"
	echo "$MY_HADOOP_HOME/bin/hadoop namenode -format -force 2>&1"
	if [[ "$?" != 0 ]]; then
		echo "$PREFIX ERROR: Namenode format failed."
		exit 1
	fi
}

formatDirOnSlaves $MAPRED_LOCAL_DIR
formatDirOnSlaves $DFS_DATA_DIR
formatDirOnMaster $HADOOP_TMP_DIR
formatDirOnMaster $DFS_NAME_DIR
formatNamenode
echo "$PREFIX Format successfully completed."
exit 0
