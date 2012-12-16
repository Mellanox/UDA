#!/bin/bash

is_LZO_in_Lib64=`whereis liblzo2 | awk \
'BEGIN { FS = " "} ;
	{ 
	for (i=1; i<NF+1; i++) { 
		if ($i=="/usr/lib64/liblzo2.so")
			{ a="good"; } 
		} 
	} 
	
	END {print a; } '`
	
    if [ "$is_LZO_in_Lib64" == "good" ]; then
		echo "---->>> lzo is in: /usr/lib64"
		for slave in `cat $MY_HADOOP_HOME/$HADOOP_CONF_RELATIVE_PATH/slaves`
			do
				echo " $(basename $0) sudo scp /usr/lib64/liblzo2.* $slave:/usr/lib64/"
				sudo scp /usr/lib64/liblzo2.* $slave:/usr/lib64/
			done
		
		
	else 
	
	is_LZO_in_usr_local_lib=`whereis liblzo2 | awk \
	'BEGIN { FS = " "} ;
	{ 
	for (i=1; i<NF+1; i++) { 
		if ($i=="/usr/local/lib/liblzo2.so")
			{ a="good"; } 
		} 
	} 
	
	END {print a; } '`
	
		if [ "$is_LZO_in_usr_local_lib" == "good" ]; then
			echo "---->>> lzo is in: /usr/local/lib"
			for slave in `cat $MY_HADOOP_HOME/$HADOOP_CONF_RELATIVE_PATH/slaves`
				do
					echo " $(basename $0) scp /usr/local/lib/liblzo2.* $slave:/usr/lib64/"
					sudo scp /usr/lib64/liblzo2.* $slave:/usr/lib64/
				done
		
		else
			echo "LZO NOT installed! , installing...."
			echo "sudo scp /.autodirect/mtrswgwork/shania/hadoop/lzoSo/liblzo2.* /usr/lib64/"
			sudo scp /.autodirect/mtrswgwork/shania/hadoop/lzoSo/liblzo2.* /usr/lib64/
			echo "GET BACK HERE!!! IMPORTANT!!"
			
		fi

	
	fi
	
	