# Build the Alfred workflow package.
#   make                  -> dist/alfred-gh.alfredworkflow
#   make VERSION=1.2.3    -> same, with info.plist "version" set to 1.2.3
#   make lint             -> syntax-check the scripts and lint info.plist
#   make test             -> offline smoke tests (test/run.sh)
NAME    := alfred-gh
DIST    := dist
OUT     := $(DIST)/$(NAME).alfredworkflow
SRC     := src/info.plist src/filter.sh src/prs.sh src/lib.sh src/icon.png
VERSION ?=

.PHONY: all build lint test clean
all: $(OUT)
build: $(OUT)

$(OUT): $(SRC)
	command rm -rf $(DIST)/build
	mkdir -p $(DIST)/build
	cp $(SRC) $(DIST)/build/
	chmod +x $(DIST)/build/filter.sh $(DIST)/build/prs.sh
ifneq ($(VERSION),)
	plutil -replace version -string "$(VERSION)" $(DIST)/build/info.plist
endif
	command rm -f $@
	cd $(DIST)/build && zip -q -X ../$(NAME).alfredworkflow info.plist filter.sh prs.sh lib.sh icon.png
	command rm -rf $(DIST)/build

# The scripts are zsh. ShellCheck does not support zsh (it would
# misreport zsh-only syntax such as ${=q}, ${words[1,-2]} and glob qualifiers),
# so we only run zsh's own syntax check here.
lint:
	zsh -n src/filter.sh
	zsh -n src/prs.sh
	zsh -n src/lib.sh
	zsh -n test/run.sh
	plutil -lint src/info.plist

test:
	zsh test/run.sh

clean:
	command rm -rf $(DIST)
