GO := CGO_ENABLED=0 go
GO_TAGS ?=
TARGET=cilium
INSTALL = $(QUIET)install
BINDIR ?= /usr/local/bin
VERSION=$(shell cat VERSION)
GIT_BRANCH = $(shell which git >/dev/null 2>&1 && git rev-parse --abbrev-ref HEAD)
GIT_HASH = $(shell which git >/dev/null 2>&1 && git rev-parse --short HEAD)

TEST_TIMEOUT ?= 5s
RELEASE_UID ?= $(shell id -u)
RELEASE_GID ?= $(shell id -g)

GOLANGCILINT_WANT_VERSION = 1.40.1
GOLANGCILINT_VERSION = $(shell golangci-lint version 2>/dev/null)

$(TARGET):
	$(GO) build $(if $(GO_TAGS),-tags $(GO_TAGS)) \
		-ldflags "-w -s \
		-X 'github.com/cilium/cilium-cli/internal/cli/cmd.GitBranch=${GIT_BRANCH}' \
		-X 'github.com/cilium/cilium-cli/internal/cli/cmd.GitHash=$(GIT_HASH)' \
		-X 'github.com/cilium/cilium-cli/internal/cli/cmd.Version=${VERSION}'" \
		-o $(TARGET) \
		./cmd/cilium

release:
	docker run \
		--env "RELEASE_UID=$(RELEASE_UID)" \
		--env "RELEASE_GID=$(RELEASE_GID)" \
		--rm \
		--workdir /cilium \
		--volume `pwd`:/cilium docker.io/library/golang:1.16.6-alpine3.13 \
		sh -c "apk add --no-cache make && make local-release"

local-release: clean
	for OS in darwin linux; do \
		EXT=; \
		ARCHS=; \
		case $$OS in \
			darwin) \
				ARCHS='amd64 arm64'; \
				;; \
			linux) \
				ARCHS='386 amd64 arm arm64'; \
				;; \
		esac; \
		for ARCH in $$ARCHS; do \
			echo Building release binary for $$OS/$$ARCH...; \
			test -d release/$$OS/$$ARCH|| mkdir -p release/$$OS/$$ARCH; \
			env GOOS=$$OS GOARCH=$$ARCH $(GO) build $(if $(GO_TAGS),-tags $(GO_TAGS)) -ldflags "-w -s -X 'github.com/cilium/cilium-cli/internal/cli/cmd.Version=${VERSION}'" -o release/$$OS/$$ARCH/$(TARGET)$$EXT ./cmd/cilium; \
			tar -czf release/$(TARGET)-$$OS-$$ARCH.tar.gz -C release/$$OS/$$ARCH $(TARGET)$$EXT; \
			(cd release && sha256sum $(TARGET)-$$OS-$$ARCH.tar.gz > $(TARGET)-$$OS-$$ARCH.tar.gz.sha256sum); \
		done; \
		rm -r release/$$OS; \
	done; \
	if [ $$(id -u) -eq 0 -a -n "$$RELEASE_UID" -a -n "$$RELEASE_GID" ]; then \
		chown -R "$$RELEASE_UID:$$RELEASE_GID" release; \
	fi

install: $(TARGET)
	$(INSTALL) -m 0755 -d $(DESTDIR)$(BINDIR)
	$(INSTALL) -m 0755 $(TARGET) $(DESTDIR)$(BINDIR)

clean:
	rm -f $(TARGET)
	rm -rf ./release

test:
	go test -timeout=$(TEST_TIMEOUT) -race -cover $$(go list ./...)

bench:
	go test -timeout=30s -bench=. $$(go list ./...)

ifneq (,$(findstring $(GOLANGCILINT_WANT_VERSION),$(GOLANGCILINT_VERSION)))
check:
	golangci-lint run
else
check:
	docker run --rm -v `pwd`:/app -w /app docker.io/golangci/golangci-lint:v$(GOLANGCILINT_WANT_VERSION) golangci-lint run
endif

.PHONY: $(TARGET) release local-release install clean test bench check
