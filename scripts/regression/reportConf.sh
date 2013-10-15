#!/bin/sh
	
	# colors
export STANDARD_BGCOLOR="White"
export STANDARD_FONT_COLOR="Black"
export SUCCESS_BGCOLOR="GreenYellow"
export SUCCESS_FONT_COLOR=$STANDARD_FONT_COLOR
export WARN_BGCOLOR="Gold"
export WARN_FONT_COLOR=$STANDARD_FONT_COLOR
export ERROR_BGCOLOR="Crimson"
export ERROR_FONT_COLOR=$STANDARD_FONT_COLOR
export FATAL_BGCOLOR="Maroon"
export FATAL_FONT_COLOR="White"
export FILL_COLOR_1="LightSkyBlue"
export FILL_COLOR_2="MediumOrchid"
export FILL_COLOR_3="Lavender"
export FILL_COLOR_4="AntiqueWhite"
export FILL_COLOR_5="White"
export FONT_COLOR_1="DodgerBlue"
export FONT_COLOR_2="Navy"

export REPORT_TYPE="html"
export SUCCESS_CODE="&#10003"
export FAILURE_CODE="&#10007"
export BAD_MAPPERS_THRESHOLD=10

export PI_TABLE_ATTR="border='1' cellpadding='2' cellspacing='1' width='100%'"

export TERASORT_STATISTICS_NAMES="
<tr bgcolor='CornflowerBlue'>
	<td>Summary</td>
	<td>Count</td>
	<td>Avergae</td>
	<td>Min Result</td>  
	<td>Max Result</td>
	<td>Std-Dev</td>
</tr>"

export TERASORT_TESTS_NAMES="
<tr bgcolor='$FILL_COLOR_1'>
	<td>test #</td>
	<td>Job Staus</td>
	<td>Cores</td>
	<td>Job Duration (hadoop measurement)</td>
	<td>Job Duration (our measurements)</td>
	<td>Map Time</td>
	<td>Reduce Time</td>
	<td>Teravalidate</td>
	<td>input=output</td>
	<td>Lunched Map Tasks</td>
	<td>Failed Map Tasks</td>
	<td>Killed Map Tasks</td>
	<td>Lunched Reduce Tasks</td>
	<td>Failed Reduce Tasks</td>
	<td>Killed Reduce Tasks</td>
</tr>"

export ROW_BREAKER="<br>"