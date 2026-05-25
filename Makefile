EMACS ?= emacs

TEST_FILES := $(wildcard test/*-tests.el)

.PHONY: test
test:
	$(EMACS) -Q --batch \
	  -L elisp \
	  -L test \
	  $(addprefix -l ,$(TEST_FILES)) \
	  -f ert-run-tests-batch-and-exit
