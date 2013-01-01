#!/bin/awk

BEGIN{
	duration=0
	split(timeLine,tmp,", ")

	for (i in tmp)
	{
		type=tmp[i]
		val=tmp[i]
		gsub(/[0-9)]+/, "" , type)
		gsub(/[a-z)]+/, "" , val)
		
		if (type ~ /sec/)
			duration=duration+val
		else if (type ~ /min/)
			duration=duration+60*val
		else if (type ~ /hrs/)
			duration=duration+3600*val
	}
} 

END {
	print duration
}
