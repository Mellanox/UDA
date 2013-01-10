#
# note: this Makefile assumes you performed ./src/premake.sh once
#
SUBDIRS = src plugins

.PHONY: subdirs $(SUBDIRS)
     
subdirs: $(SUBDIRS)
     
$(SUBDIRS):
	 $(MAKE) -C $@
