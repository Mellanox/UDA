#!/bin/bash

echoPrefix=$(basename $0)

echo "$echoPrefix: creating report-tables file at $REPORT_INPUT_DIR"
touch $REPORT_INPUT_DIR/analizeResults.txt

if [[ -n "$TERASORT_RESULTS_INPUT_DIR" ]];then
    bash $SCRIPTS_DIR/terasortAnallizer.sh
fi

if [[ -n "$TEST_DFSIO_RESULTS_INPUT_DIR" ]];then
    echo ""
fi

if [[ -n "$PI_RESULTS_INPUT_DIR" ]];then
    bash $SCRIPTS_DIR/piAnallizer.sh
fi

echo "#!/bin/sh
" > $TMP_DIR/analizeExports.sh