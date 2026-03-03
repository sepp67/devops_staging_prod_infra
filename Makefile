.PHONY: lint
lint:
	yamllint .
	ansible-lint -v ansible/
