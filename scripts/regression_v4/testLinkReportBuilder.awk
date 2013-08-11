#!/bin/awk -f

BEGIN{
	testName=1
	passedTests=2
	totalTests=3

	i=1
	passedCounter=0
	totalCounter=0
}

($testName ~ /[A-Za-z0-9_]+/){
	arrNames[i]=$testName
	arrPassed[i]=$passedTests
	arrTotals[i]=$totalTests
	
	i++
	passedCounter+=$passedTests
	totalCounter+=$totalTests"/"$totalTests
}

END{
	print "<p><h3>Functionality tests passed "passedCounter" out of "totalCounter"</h3></p>"
	print "<table " tableProperties ">"
		print "	<tr>"
			print "		<th>Test Name</th>"
			print "		<th>passed/total</th>"
		print "	</tr>"
	for (j=1;j<i;j++)
	{
		if (arrPassed[j] == arrTotals[j])
			statusColor=successColor
		else
			statusColor=failureColor
			
		print "	<tr>"
			print "		<td>" arrNames[j] "</td>"
			print "		<td bgcolor="statusColor">" arrPassed[j]"/"arrTotals[j] "</td>"
		print "	</tr>"
	}
	print "</table>"
}
