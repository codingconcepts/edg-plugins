validate_version:
ifndef VERSION
	$(error VERSION is undefined)
endif

tag: validate_version
	git tag ${VERSION}
	git push origin ${VERSION}