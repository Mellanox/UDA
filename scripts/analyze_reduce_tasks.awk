#!/bin/awk -f

BEGIN { RS=" "; FS="="; mapCount=0; shuffleCount=0; mergeCount=0; reduceCount=0; currAttempt="map"; appears=0 }


/TASK_TYPE/{
	if ($2=="\"MAP\""){ 
		currAttempt="map"; 
	}
	else if ($2=="\"REDUCE\""){
		currAttempt="reduce"; 
	}
	else {
		currAttempt="skip"	
		next;
	}
}


/TASK_STATUS/{
	appears=(appears+1)%2
	if (!appears)
		next;
}

/START_TIME/{
	if (appears){
		if (currAttempt=="map")
			mapCount++;
		else if (currAttempt=="reduce")
			shuffleCount++;
		printf("START_TIME --- \t\tTime:%s  Map:%d  Shuffle:%d  Merge:%d  Reduce:%d   Attempt:%s\n", $2 ,mapCount, shuffleCount, mergeCount, reduceCount, currAttempt);
	}
}


/SHUFFLE_FINISHED/{ 
		if (currAttempt=="reduce"){
			shuffleCount--;
			mergeCount++;
			printf("SHUFFLE_FINISHED --- \tTime:%s  Map:%d  Shuffle:%d  Merge:%d  Reduce:%d   Attempt:%s\n", $2 ,mapCount, shuffleCount, mergeCount, reduceCount, currAttempt);
		}
	
}

/SORT_FINISHED/{
		if (currAttempt=="reduce"){
			mergeCount--;
			reduceCount++;
			printf("SORT_FINISHED --- \tTime:%s  Map:%d  Shuffle:%d  Merge:%d  Reduce:%d   Attempt:%s\n", $2 ,mapCount, shuffleCount, mergeCount, reduceCount, currAttempt);
		}
	
}

/FINISH_TIME/{
	if (appears){	
		if (currAttempt=="map" )
			mapCount--;
		else if (currAttempt=="reduce") 
			reduceCount--;
		printf("FINISH_TIME --- \tTime:%s  Map:%d  Shuffle:%d  Merge:%d  Reduce:%d   Attempt:%s\n", $2 ,mapCount, shuffleCount, mergeCount, reduceCount, currAttempt);
	}
	
}

 
