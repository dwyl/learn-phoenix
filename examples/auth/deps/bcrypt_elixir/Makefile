CFLAGS ?= -g -O3
CFLAGS += -Wall -Wno-format-truncation

CFLAGS += -I"$(ERTS_INCLUDE_DIR)"
CFLAGS += -Ic_src

PRIV_DIR = $(MIX_APP_PATH)/priv
LIB_NAME = $(PRIV_DIR)/bcrypt_nif.so
ifneq ($(CROSSCOMPILE),)
    # crosscompiling
    CFLAGS += -fPIC
else
    # not crosscompiling
    ifneq ($(OS),Windows_NT)
        CFLAGS += -fPIC

        ifeq ($(shell uname),Darwin)
            LDFLAGS += -dynamiclib -undefined dynamic_lookup
        endif
    endif
endif

NIF_SRC=\
	c_src/bcrypt_nif.c\
	c_src/blowfish.c

calling_from_make:
	mix compile

all: _priv_dir _lib_name

_lib_name: $(NIF_SRC)
	$(CC) $(CFLAGS) -shared $(LDFLAGS) $^ -o "$(LIB_NAME)"

_priv_dir:
	mkdir -p "$(PRIV_DIR)"

clean:
	rm -f $(LIB_NAME)

.PHONY: all clean _priv_dir _lib_name
