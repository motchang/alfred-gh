# Build the Alfred workflow package.
#   make                  -> dist/alfred-gh.alfredworkflow
#   make VERSION=1.2.3    -> same, with info.plist "version" set to 1.2.3
#   make lint             -> syntax-check filter.sh and lint info.plist
NAME    := alfred-gh
DIST    := dist
OUT     := $(DIST)/$(NAME).alfredworkflow
SRC     := src/info.plist src/filter.sh src/icon.png
VERSION ?=

.PHONY: all lint clean
all: $(OUT)

$(OUT): $(SRC)
	command rm -rf $(DIST)/build
	mkdir -p $(DIST)/build
	cp $(SRC) $(DIST)/build/
	chmod +x $(DIST)/build/filter.sh
ifneq ($(VERSION),)
	plutil -replace version -string "$(VERSION)" $(DIST)/build/info.plist
endif
	command rm -f $@
	cd $(DIST)/build && zip -q -X ../$(NAME).alfredworkflow info.plist filter.sh icon.png
	command rm -rf $(DIST)/build

# filter.sh is a zsh script. ShellCheck does not support zsh (it would
# misreport zsh-only syntax such as ${=q}, ${words[1,-2]} and glob qualifiers),
# so we only run zsh's own syntax check here.
lint:
	zsh -n src/filter.sh
	plutil -lint src/info.plist

clean:
	command rm -rf $(DIST)
