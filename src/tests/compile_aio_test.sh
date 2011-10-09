#!/bin/bash

g++ AIOHandler_test.cc ../CommUtils/AIOHandler.cc ../CommUtils/IOUtility.cc  -o test -I../include/  -laio -lpthread -lrt

