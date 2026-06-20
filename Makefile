validate_version:
ifndef VERSION
	$(error VERSION is undefined)
endif

release:
	cd rust && trap 'cd ..' EXIT && \
		cargo login && \
		cargo publish --dry-run && \
		cargo publish

tag: validate_version
	git tag ${VERSION}
	git push origin ${VERSION}