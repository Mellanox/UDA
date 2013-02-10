SUBDIRS = mlx-1.x/  mlx-3.x/  mlx-CDH3u4/

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