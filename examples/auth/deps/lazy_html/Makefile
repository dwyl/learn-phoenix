PRIV_DIR := $(MIX_APP_PATH)/priv
NIF_PATH := $(PRIV_DIR)/liblazy_html.so
C_SRC := $(shell pwd)/c_src

CPPFLAGS := -shared -fPIC -fvisibility=hidden -std=c++17 -Wall -Wextra -Wno-unused-parameter -Wno-comment
CPPFLAGS += -I$(ERTS_INCLUDE_DIR) -I$(FINE_INCLUDE_DIR)

LEXBOR_DIR := $(shell pwd)/_build/c/third_party/lexbor/$(LEXBOR_GIT_SHA)
ifdef CC_PRECOMPILER_CURRENT_TARGET
	LEXBOR_BUILD_DIR := $(LEXBOR_DIR)/build-$(CC_PRECOMPILER_CURRENT_TARGET)
else
	LEXBOR_BUILD_DIR := $(LEXBOR_DIR)/build
endif
LEXBOR_LIB := $(LEXBOR_BUILD_DIR)/liblexbor_static.a
CPPFLAGS += -I$(LEXBOR_DIR)/source

ifdef DEBUG
	CPPFLAGS += -g
else
	CPPFLAGS += -O3
endif

ifndef TARGET_ABI
  TARGET_ABI := $(shell uname -s | tr '[:upper:]' '[:lower:]')
endif

ifeq ($(TARGET_ABI),darwin)
	CPPFLAGS += -undefined dynamic_lookup -flat_namespace
endif

SOURCES := $(wildcard $(C_SRC)/*.cpp)

all: $(NIF_PATH)
	@ echo > /dev/null # Dummy command to avoid the default output "Nothing to be done".

$(NIF_PATH): $(SOURCES) $(LEXBOR_LIB)
	@ mkdir -p $(PRIV_DIR)
	$(CXX) $(CPPFLAGS) $(SOURCES) $(LEXBOR_LIB) -o $(NIF_PATH)

$(LEXBOR_LIB): $(LEXBOR_DIR)
	@ mkdir -p $(LEXBOR_BUILD_DIR)
	# We explicitly specify CMAKE_OSX_DEPLOYMENT_TARGET, otherwise cmake
	# may assume a higher version depending on the current installation.
	cd $(LEXBOR_BUILD_DIR) && \
		cmake .. -DLEXBOR_BUILD_SHARED=OFF -DLEXBOR_BUILD_STATIC=ON -DLEXBOR_BUILD_SEPARATELY=OFF \
			-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 && \
		cmake --build .

$(LEXBOR_DIR):
	@ git clone --depth 1 https://github.com/lexbor/lexbor.git $(LEXBOR_DIR) && \
		cd $(LEXBOR_DIR) && \
		git fetch --depth 1 origin $(LEXBOR_GIT_SHA) && \
		git checkout $(LEXBOR_GIT_SHA)
