SUBDIRS = mlx-1.x/  mlx-1.x-old/ mlx-3.x/ mlx-2.x/  mlx-2.0.x/

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
