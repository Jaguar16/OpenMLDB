# Copyright 2021 4Paradigm
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
MAKEFILE_DIR  := $(dir $(MAKEFILE_PATH))
# Disable parallel build, or system freezing may happen: #882
NPROC ?= 1

CMAKE_PRG ?= $(shell (command -v cmake3 || echo cmake))
CMAKE_BUILD_TYPE ?= RelWithDebInfo
CMAKE_FLAGS := -DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE)

CMAKE_EXTRA_FLAGS ?=

SQL_CASE_BASE_DIR ?= $(MAKEFILE_DIR)
OPENMLDB_BUILD_TARGET ?= all

# Extra cmake flags for OpenMLDB
OPENMLDB_CMAKE_FLAGS := $(CMAKE_FLAGS)
ifdef SQL_PYSDK_ENABLE
    OPENMLDB_CMAKE_FLAGS += -DSQL_PYSDK_ENABLE=$(SQL_PYSDK_ENABLE)
endif
ifdef SQL_JAVASDK_ENABLE
    OPENMLDB_CMAKE_FLAGS += -DSQL_JAVASDK_ENABLE=$(SQL_JAVASDK_ENABLE)
endif
ifdef TESTING_ENABLE
    OPENMLDB_CMAKE_FLAGS += -DTESTING_ENABLE=$(TESTING_ENABLE)
endif
ifdef CMAKE_INSTALL_PREFIX
    OPENMLDB_CMAKE_FLAGS += -DCMAKE_INSTALL_PREFIX=$(CMAKE_INSTALL_PREFIX)
endif

# Extra cmake flags for HybridSE
HYBRIDSE_CMAKE_FLAGS := $(CMAKE_FLAGS)
ifdef PYSDK_ENABLE
    HYBRIDSE_CMAKE_FLAGS += -DPYSDK_ENABLE=$(PYSDK_ENABLE)
endif
ifdef HYBRIDSE_TESTING_ENABLE
    HYBRIDSE_CMAKE_FLAGS += -DHYBRIDSE_TESTING_ENABLE=$(HYBRIDSE_TESTING_ENABLE)
endif
ifdef TESTING_ENABLE
    HYBRIDSE_CMAKE_FLAGS += -DTESTING_ENABLE=$(TESTING_ENABLE)
endif
ifdef EXAMPLES_ENABLE
    HYBRIDSE_CMAKE_FLAGS += -DEXAMPLES_ENABLE=$(EXAMPLES_ENABLE)
endif
ifdef EXAMPLES_TESTING_ENABLE
    HYBRIDSE_CMAKE_FLAGS += -DEXAMPLES_TESTING_ENABLE=$(EXAMPLES_TESTING_ENABLE)
endif
ifdef COVERAGE_ENABLE
    HYBRIDSE_CMAKE_FLAGS += -DCOVERAGE_ENABLE=$(COVERAGE_ENABLE)
endif
ifdef SANITIZER_ENABLE
    HYBRIDSE_CMAKE_FLAGS += -DSANITIZER_ENABLE=$(SANITIZER_ENABLE)
endif

# append hybridse flags so it also works when compile all from OPENMLDB_BUILD_DIR
OPENMLDB_CMAKE_FLAGS += $(HYBRIDSE_CMAKE_FLAGS)

# Extra cmake flags for third-party
THIRD_PARTY_CMAKE_FLAGS ?=

ifdef BUILD_BUNDLED
    THIRD_PARTY_CMAKE_FLAGS += -DBUILD_BUNDLED=$(BUILD_BUNDLED)
endif
ifdef BUILD_ZOOKEEPER_PATCH
    THIRD_PARTY_CMAKE_FLAGS += -DBUILD_ZOOKEEPER_PATCH=$(BUILD_ZOOKEEPER_PATCH)
endif

TEST_TARGET ?=
TEST_LEVEL ?=

.PHONY: all coverage coverage-cpp coverage-java build test configure clean thirdparty openmldb-clean thirdparty-configure thirdparty-clean thirdpartybuild-clean thirdpartysrc-clean

all: build

# TODO: better note about start zookeeper and onebox
# some of the tests require zookeeper and openmldb server started before: checkout .github/workflows/coverage.yml
coverage: coverage-cpp coverage-java

coverage-cpp: coverage-configure
	$(CMAKE_PRG) --build $(OPENMLDB_BUILD_DIR) --target coverage -- -j$(NPROC) SQL_CASE_BASE_DIR=$(SQL_CASE_BASE_DIR) YAML_CASE_BASE_DIR=$(SQL_CASE_BASE_DIR)

coverage-java: coverage-configure
	$(CMAKE_PRG) --build $(OPENMLDB_BUILD_DIR) --target cp_native_so -- -j$(NPROC)
	cd java && mvn --batch-mode prepare-package

coverage-configure:
	$(MAKE) configure COVERAGE_ENABLE=ON CMAKE_BUILD_TYPE=Debug SQL_JAVASDK_ENABLE=ON TESTING_ENABLE=ON

OPENMLDB_BUILD_DIR ?= $(MAKEFILE_DIR)/build

build: configure
	$(CMAKE_PRG) --build $(OPENMLDB_BUILD_DIR) --target $(OPENMLDB_BUILD_TARGET) -- -j$(NPROC)

install: build
	$(CMAKE_PRG) --build $(OPENMLDB_BUILD_DIR) --target install -- -j$(NPROC)

test:
	$(MAKE) build TESTING_ENABLE=ON
	bash steps/ut.sh $(TEST_TARGET) $(TEST_LEVEL)

# trick: for those compile inside hybridsql docker image, thirdparty is pre-installed in /deps/usr, will skip make thirdparty
configure: thirdparty
	if [ $(THIRD_PARTY_DIR) != "/deps/usr" ] ; then \
	    $(MAKE) thirdparty; \
	fi
	$(CMAKE_PRG) -S . -B $(OPENMLDB_BUILD_DIR) -DCMAKE_PREFIX_PATH=$(THIRD_PARTY_DIR) $(OPENMLDB_CMAKE_FLAGS) $(CMAKE_EXTRA_FLAGS)

openmldb-clean:
	rm -rf "$(OPENMLDB_BUILD_DIR)"

THIRD_PARTY_BUILD_DIR ?= $(MAKEFILE_DIR)/.deps
THIRD_PARTY_SRC_DIR ?= $(MAKEFILE_DIR)/thirdsrc
THIRD_PARTY_DIR ?= $(THIRD_PARTY_BUILD_DIR)/usr

# third party compiled code install to 'OpenMLDB/.deps/usr', source code install to 'OpenMLDB/thirdsrc'
thirdparty: thirdparty-configure
	$(CMAKE_PRG) --build $(THIRD_PARTY_BUILD_DIR)

thirdparty-configure:
	$(CMAKE_PRG) -S third-party -B $(THIRD_PARTY_BUILD_DIR) -DSRC_INSTALL_DIR=$(THIRD_PARTY_SRC_DIR) $(THIRD_PARTY_CMAKE_FLAGS)

thirdparty-clean: thirdpartybuild-clean thirdpartysrc-clean

thirdpartybuild-clean:
	rm -rf "$(THIRD_PARTY_BUILD_DIR)"

thirdpartysrc-clean:
	rm -rf "$(THIRD_PARTY_SRC_DIR)"

HYBRIDSE_BUILD_DIR := $(MAKEFILE_DIR)/hybridse/build
HYBRIDSE_INSTALL_DIR := $(THIRD_PARTY_DIR)/hybridse

.PHONY: hybridse hybridse-build hybridse-test hybridse-configure hybridse-coverage hybridse-coverage-configure hybridse-clean

# hybridse* target reserved for those like to compile in the old way
hybridse: hybridse-build

hybridse-install: hybridse-build
	$(CMAKE_PRG) --build $(HYBRIDSE_BUILD_DIR) --target install

hybridse-test: hybridse-build
	$(CMAKE_PRG) --build $(HYBRIDSE_BUILD_DIR) --target test -- -j$(NPROC) SQL_CASE_BASE_DIR=$(SQL_CASE_BASE_DIR) 

hybridse-build: hybridse-configure
	$(CMAKE_PRG) --build $(HYBRIDSE_BUILD_DIR) -- -j$(NPROC)

hybridse-configure: thirdparty
	$(CMAKE_PRG) -S hybridse -B $(HYBRIDSE_BUILD_DIR) -DCMAKE_PREFIX_PATH=$(THIRD_PARTY_DIR) -DCMAKE_INSTALL_PREFIX=$(HYBRIDSE_INSTALL_DIR) $(HYBRIDSE_CMAKE_FLAGS) $(CMAKE_EXTRA_FLAGS)

hybridse-coverage: hybridse-coverage-configure
	$(CMAKE_PRG) --build $(HYBRIDSE_BUILD_DIR) -- -j$(NPROC)
	$(CMAKE_PRG) --build $(HYBRIDSE_BUILD_DIR) --target coverage -- -j$(NPROC) SQL_CASE_BASE_DIR=$(SQL_CASE_BASE_DIR) YAML_CASE_BASE_DIR=$(SQL_CASE_BASE_DIR)

hybridse-coverage-configure:
	$(MAKE) hybridse-configure CMAKE_BUILD_TYPE=Debug COVERAGE_ENABLE=ON

hybridse-clean:
	rm -rf "$(HYBRIDSE_BUILD_DIR)"

clean: hybridse-clean openmldb-clean

.PHONY: distclean lint format javafmt shfmt cppfmt pyfmt configfmt yamlfmt jsonfmt xmlfmt cpplint shlint javalint pylint

distclean: clean thirdparty-clean

lint: cpplint shlint javalint pylint

format: javafmt shfmt cppfmt pyfmt configfmt

javafmt:
	@cd java && mvn -pl hybridse-sdk spotless:apply

shfmt:
	@if command -v shfmt; then\
	    git ls-files | grep --regexp "\.sh$$" | xargs -I {} shfmt -i 4 -w {}; \
	    exit 0; \
	    else \
	    echo "SKIP: shfmt (shfmt not found)"; \
	    fi

cppfmt:
	@if command -v clang-format; then \
	    git ls-files | grep --regexp "\(\.h\|\.cc\)$$" | xargs -I {} clang-format -i -style=file {} ; \
	    exit 0; \
	    else \
	    echo "SKIP: cppfmt (clang-format not found)"; \
	    fi

pyfmt:
	@if command -v yapf; then \
	    git ls-files | grep --regexp "\.py$$" | xargs -I {} yapf -i --style=google {}; \
	    exit 0; \
	    else \
	    echo "SKIP: pyfmt (yapf not found)"; \
	    fi

configfmt: yamlfmt jsonfmt

yamlfmt:
	@if command -v prettier; then \
	    git ls-files | grep --regexp "\(\.yaml\|\.yml\)$$" | xargs -I {} prettier -w {}; \
	    exit 0; \
	    else \
	    echo "SKIP: yamlfmt (prettier not found)"; \
	    fi

jsonfmt:
	@if command -v prettier; then \
	    git ls-files | grep --regexp "\.json$$" | xargs -I {} prettier -w {}; \
	    exit 0; \
	    else \
	    echo "SKIP: jsonfmt (prettier not found)"; \
	    fi

xmlfmt:
	@if command -v prettier; then \
	    git ls-files | grep --regexp "\.xml$$" | xargs -I {} prettier --plugin=@prettier/plugin-xml --plugin-search-dir=./node_modules -w {}; \
	    exit 0; \
	    else \
	    echo "SKIP: xmlfmt (prettier not found)"; \
	    fi


cpplint:
	@if command -v cpplint; then \
	    git ls-files | grep --regexp "\(\.h\|\.cc\)$$" | xargs -I {} cpplint {} ; \
	    else \
	    echo "SKIP: cpplint (cpplint not found)"; \
	    fi

shlint:
	@if command -v shellcheck; then \
	    git ls-files | grep --regexp "\.sh$$" | xargs -I {} shellcheck {}; \
	    else \
	    echo "SKIP: shlint (shellcheck not found)"; \
	    fi

javalint:
	@cd java && mvn -pl hybridse-sdk -Dplugin.violationSeverity=warning checkstyle:check

pylint:
	@if command -v pylint; then \
	    git ls-files | grep --regexp "\.py$$" | xargs -I {} pylint {}; \
	    else \
	    echo "SKIP: pylint (pylint not found)"; \
	    fi
