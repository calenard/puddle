# Local / untagged builds ship as 0.0.0. Release builds are driven by
# goreleaser which overrides VERSION from the git tag.
VERSION ?= 0.0.0
LDFLAGS := -s -w -X main.version=$(VERSION)

.PHONY: build install test lint fmt clean release run

build:
	go build -trimpath -ldflags "$(LDFLAGS)" -o bin/puddle ./cmd/puddle

install:
	go install -ldflags "$(LDFLAGS)" ./cmd/puddle

test:
	go test -race ./...

run: build
	./bin/puddle

lint:
	go vet ./...
	@test -z "$$(gofmt -l . | tee /dev/stderr)" || (echo "gofmt issues"; exit 1)

fmt:
	gofmt -w .

clean:
	rm -rf bin

release:
	@mkdir -p bin
	GOOS=linux   GOARCH=amd64 go build -trimpath -ldflags "$(LDFLAGS)" -o bin/puddle-linux-amd64   ./cmd/puddle
	GOOS=linux   GOARCH=arm64 go build -trimpath -ldflags "$(LDFLAGS)" -o bin/puddle-linux-arm64   ./cmd/puddle
	GOOS=darwin  GOARCH=amd64 go build -trimpath -ldflags "$(LDFLAGS)" -o bin/puddle-darwin-amd64  ./cmd/puddle
	GOOS=darwin  GOARCH=arm64 go build -trimpath -ldflags "$(LDFLAGS)" -o bin/puddle-darwin-arm64  ./cmd/puddle
	GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "$(LDFLAGS)" -o bin/puddle-windows-amd64.exe ./cmd/puddle
