SUBDIRS = mlx-1.x-v2/  mlx-1.x-v1/  mlx-1.x-cdh-4.2/  mlx-3.x/  mlx-CDH3u4/

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
