#!/usr/bin/env python

# Built-in modules
import sys

from reg2_wrapper.test_wrapper.standalone_wrapper import StandaloneWrapper
from reg2_wrapper.utils.parser.cmd_argument import RunningStage

class UdaWrapper(StandaloneWrapper):

    def get_command(self, running_stage=RunningStage.RUN):
        return "./runRegression.sh"

if __name__ == "__main__":
    wrapper = UdaWrapper("UDA Wrapper")
    wrapper.execute(sys.argv[1:])

