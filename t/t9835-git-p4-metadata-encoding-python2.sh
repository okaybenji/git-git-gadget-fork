#!/bin/sh

test_description='git p4 metadata encoding

This test checks that the import process handles inconsistent text
encoding in p4 metadata (author names, commit messages, etc) without
failing, and produces maximally sane output in git.'

. ./lib-git-p4.sh

python_target_version='2'

###############################
## SECTION REPEATED IN t9836 ##
###############################

# HORRIBLE HACK TO ENSURE PYTHON VERSION!
# Weirdnesses:
#  - Looking for python2 and python3 in a very specific path (/usr/bin/)
#  - Code is inelegant
#  - Code is duplicated (like most of this test script)
#  - Test calls "git-p4.py" rather than "git-p4", because the latter references a specific path

python_major_version=$(python -V 2>&1 | cut -c  8)
python_target_exists=$(/usr/bin/python$python_target_version -V 2>&1)
if ! test "$python_major_version" = "$python_target_version" && test "$python_target_exists"
then
	mkdir temp_python
	PATH="$(pwd)/temp_python:$PATH" && export PATH
	ln -s /usr/bin/python$python_target_version temp_python/python
fi

python_major_version=$(python -V 2>&1 | cut -c  8)
if ! test "$python_major_version" = "$python_target_version"
then
	skip_all="skipping python$python_target_version-specific git p4 tests; python$python_target_version not available"
	test_done
fi

remove_user_cache () {
	rm "$HOME/.gitp4-usercache.txt" || true
}

test_expect_success 'start p4d' '
	start_p4d
'

test_expect_success 'init depot' '
	(
		cd "$cli" &&

		p4_add_user "utf8_author" "ǣuthor" &&
		P4USER=utf8_author &&
		touch file1 &&
		p4 add file1 &&
		p4 submit -d "first CL has some utf-8 tǣxt" &&

		p4_add_user "latin1_author" "$(echo æuthor |
			iconv -f utf8 -t latin1)" &&
		P4USER=latin1_author &&
		touch file2 &&
		p4 add file2 &&
		p4 submit -d "$(echo second CL has some latin-1 tæxt |
			iconv -f utf8 -t latin1)" &&

		p4_add_user "cp1252_author" "$(echo æuthœr |
			iconv -f utf8 -t cp1252)" &&
		P4USER=cp1252_author &&
		touch file3 &&
		p4 add file3 &&
		p4 submit -d "$(echo third CL has sœme cp-1252 tæxt |
		  iconv -f utf8 -t cp1252)"
	)
'

test_expect_success 'clone non-utf8 repo with strict encoding' '
	test_when_finished cleanup_git &&
	test_when_finished remove_user_cache &&
	test_must_fail git -c git-p4.metadataDecodingStrategy=strict p4.py clone --dest="$git" //depot@all 2>err &&
	grep "Decoding returned data failed!" err
'

test_expect_success 'check utf-8 contents with legacy strategy' '
	test_when_finished cleanup_git &&
	test_when_finished remove_user_cache &&
	git -c git-p4.metadataDecodingStrategy=legacy p4.py clone --dest="$git" //depot@all &&
	(
		cd "$git" &&
		git log >actual &&
		grep "some utf-8 tǣxt" actual &&
		grep "ǣuthor" actual
	)
'

test_expect_success 'check latin-1 contents corrupted in git with legacy strategy' '
	test_when_finished cleanup_git &&
	test_when_finished remove_user_cache &&
	git -c git-p4.metadataDecodingStrategy=legacy p4.py clone --dest="$git" //depot@all &&
	(
		cd "$git" &&
		git log >actual &&
		badly_encoded_in_git=$(echo "some latin-1 tæxt" | iconv -f utf8 -t latin1) &&
		grep "$badly_encoded_in_git" actual &&
		bad_author_in_git="$(echo æuthor | iconv -f utf8 -t latin1)" &&
		grep "$bad_author_in_git" actual
	)
'

test_expect_success 'check utf-8 contents with fallback strategy' '
	test_when_finished cleanup_git &&
	test_when_finished remove_user_cache &&
	git -c git-p4.metadataDecodingStrategy=fallback p4.py clone --dest="$git" //depot@all &&
	(
		cd "$git" &&
		git log >actual &&
		grep "some utf-8 tǣxt" actual &&
		grep "ǣuthor" actual
	)
'

test_expect_success 'check latin-1 contents with fallback strategy' '
	test_when_finished cleanup_git &&
	test_when_finished remove_user_cache &&
	git -c git-p4.metadataDecodingStrategy=fallback p4.py clone --dest="$git" //depot@all &&
	(
		cd "$git" &&
		git log >actual &&
		grep "some latin-1 tæxt" actual &&
		grep "æuthor" actual
	)
'

test_expect_success 'check cp-1252 contents with fallback strategy' '
	test_when_finished cleanup_git &&
	test_when_finished remove_user_cache &&
	git -c git-p4.metadataDecodingStrategy=fallback p4.py clone --dest="$git" //depot@all &&
	(
		cd "$git" &&
		git log >actual &&
		grep "sœme cp-1252 tæxt" actual &&
		grep "æuthœr" actual
	)
'

test_expect_success 'check cp-1252 contents on later sync after clone with fallback strategy' '
	test_when_finished cleanup_git &&
	test_when_finished remove_user_cache &&
	git -c git-p4.metadataDecodingStrategy=fallback p4.py clone --dest="$git" //depot@all &&
	(
		cd "$cli" &&
		P4USER=cp1252_author &&
		touch file4 &&
		p4 add file4 &&
		p4 submit -d "$(echo fourth CL has sœme more cp-1252 tæxt |
			iconv -f utf8 -t cp1252)"
	) &&
	(
		cd "$git" &&

		git p4.py sync --branch=master &&

		git log p4/master >actual &&
		cat actual &&
		grep "sœme more cp-1252 tæxt" actual &&
		grep "æuthœr" actual
	)
'

############################
## / END REPEATED SECTION ##
############################

test_expect_success 'legacy (latin-1 contents corrupted in git) is the default with python2' '
	test_when_finished cleanup_git &&
	test_when_finished remove_user_cache &&
	git -c git-p4.metadataDecodingStrategy=legacy p4.py clone --dest="$git" //depot@all &&
	(
		cd "$git" &&
		git log >actual &&
		badly_encoded_in_git=$(echo "some latin-1 tæxt" | iconv -f utf8 -t latin1) &&
		grep "$badly_encoded_in_git" actual
	)
'

test_done
