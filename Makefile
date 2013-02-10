#
# note: this Makefile assumes you performed ./src/premake.sh once
#
SUBDIRS = src plugins

.PHONY: all $(SUBDIRS)
     
all: $(SUBDIRS)
     
$(SUBDIRS):
	 $(MAKE) -C $@


CLEANDIRS = $(SUBDIRS:%=clean-%)

clean: $(CLEANDIRS)
$(CLEANDIRS): 
	$(MAKE) -C $(@:clean-%=%) clean

.PHONY: $(CLEANDIRS)
.PHONY: clean