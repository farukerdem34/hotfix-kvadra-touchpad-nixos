MODULE		:= hotfix-kvadra-touchpad

obj-m 		:= $(MODULE).o
$(MODULE)-objs	:= module.o

PWD := $(shell pwd)

all:
	echo $(PWD)
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
