REGISTRY_HOST=docker.io
USERNAME=akomic
NAME=$(shell basename $(PWD))
VERSION=$(shell cat .release)

.PHONY: list build push clean

list:
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' | xargs
build:
	docker build -f Dockerfile -t $(REGISTRY_HOST)/$(USERNAME)/$(NAME):$(VERSION) .
push:
	docker push $(REGISTRY_HOST)/$(USERNAME)/$(NAME):$(VERSION)
clean:
	docker rmi $(USERNAME)/$(NAME):$(VERSION)

all: build push clean
