#!/usr/bin/env bats

load ../helper

BEFORE_PULL_TAG=__homeshick-before-pull__
assert_tag_is_removed() {
	for castle in "$@"; do
		(
			cd "$HOME/.homesick/repos/$castle" || return $?
			# show all the tags if the test fails
			git show-ref --tags >&2 || true
			# this tag should not exist
			run git rev-parse --verify "refs/tags/$BEFORE_PULL_TAG" >&2 2>&-
			[ "$status" -ne 0 ] # should fail
		)
	done
}

reset_and_add_new_file() {
	(
		cd "$HOME/.homesick/repos/pull-test" || return $?
		git reset --hard "$1" >/dev/null

		git config user.name "Homeshick user"
		git config user.email "homeshick@example.com"

		cat > home/.ignore <<EOF
.DS_Store
*.swp
EOF
		git add home/.ignore >/dev/null
		git commit -m 'Added .ignore file' >/dev/null
	)
	homeshick link --batch pull-test >/dev/null
}

expect_new_files() {
	local castle="$1"
	local file="$2"
	local open_bracket="\\u005b"
	local close_bracket="\\u005d"
	local esc="\\u001b$open_bracket"
	local green="${esc}1;32m"
	local cyan="${esc}1;36m"
	local white="${esc}1;37m"
	local reset="${esc}0m"
	cat <<EOF | expect -f -
			spawn "$HOMESHICK_DIR/bin/homeshick" pull "$castle"
			expect -ex "${cyan}         pull${reset} $castle\r${green}         pull${reset} $castle\r
${white}      updates${reset} The castle $castle has new files.\r
${cyan}     symlink?${reset} ${open_bracket}yN${close_bracket} " {} default {exit 1}
			send "y\n"
			expect -ex "y\r${green}     symlink?${reset} ${open_bracket}yN${close_bracket} \r
${cyan}      symlink${reset} ${file}\r${green}      symlink${reset} ${file}\r\n" {} default {exit 1}
			expect eof {} "?" {exit 1} default {exit 1}
EOF
	assert_tag_is_removed "$castle"
}

expect_no_new_files() {
	local castle="$1"
	local open_bracket="\\u005b"
	local close_bracket="\\u005d"
	local esc="\\u001b$open_bracket"
	local green="${esc}1;32m"
	local cyan="${esc}1;36m"
	local reset="${esc}0m"
	cat <<EOF | expect -f -
			spawn "$HOMESHICK_DIR/bin/homeshick" pull --batch "$castle"
			expect -ex "${cyan}         pull${reset} $castle\r${green}         pull${reset} $castle\r\n" {} default {exit 1}
			# if there is any other output left, then fail
			expect eof {} "?" {exit 1} default {exit 1}
EOF
	assert_tag_is_removed "$castle"
}

@test 'pull skips castles with no upstream remote' {
	castle 'rc-files'
	castle 'dotfiles'
	# The dotfiles FETCH_HEAD should not exist after cloning
	[ ! -e "$HOMESICK/repos/dotfiles/.git/FETCH_HEAD" ]
	(cd "$HOMESICK/repos/rc-files" && git remote rm origin)
	run "$HOMESHICK_FN" pull rc-files dotfiles
	[ $status -eq 0 ] # EX_SUCCESS
	assert_tag_is_removed rc-files dotfiles
	# dotfiles FETCH_HEAD should exist if the castle was pulled
	[ -e "$HOMESICK/repos/dotfiles/.git/FETCH_HEAD" ]
}

@test 'pull prompts for symlinking if new files are present' {
	local castle=rc-files
	castle "$castle"
	(cd "$HOME/.homesick/repos/$castle" && git reset --hard HEAD~1 >/dev/null)
	homeshick link --batch --quiet "$castle"

	[ ! -e "$HOME/.gitignore" ]
	expect_new_files "$castle" .gitignore
	[ -f "$HOME/.gitignore" ]
}

@test 'pull prompts for symlinking with renamed files' {
	local castle=pull-renamed
	castle "$castle"
	# reset to before .bashrc-wrong-name was renamed to .bashrc
	(cd "$HOME/.homesick/repos/$castle" && git reset --hard HEAD~2 >/dev/null)
	homeshick link --batch --quiet "$castle"

	[ ! -e "$HOME/.bashrc" ]
	expect_new_files "$castle" .bashrc
	[ -f "$HOME/.bashrc" ]
}

@test 'pull with no new files present' {
	local castle=pull-test
	castle "$castle"
	(cd "$HOME/.homesick/repos/$castle" && git reset --hard HEAD~1 >/dev/null)

	expect_no_new_files "$castle"
}

@test 'pull a recently-pulled castle again' {
	# this checks that we don't try to link files again if the last operation was
	# a pull
	local castle=rc-files
	castle "$castle"
	(cd "$HOME/.homesick/repos/$castle" && git reset --hard HEAD~1 >/dev/null)
	homeshick link --batch --quiet "$castle"
	homeshick pull --batch --force "$castle"

	expect_no_new_files "$castle"
}

@test 'pull a castle with a git conflict' {
	local castle=pull-test
	castle "$castle"
	reset_and_add_new_file HEAD~2
	(cd "$HOME/.homesick/repos/$castle" && git config pull.rebase false && git config pull.ff only)

	[ ! -e "$HOME/.gitignore" ]
	local open_bracket="\\u005b"
	local close_bracket="\\u005d"
	local esc="\\u001b$open_bracket"
	local red="${esc}1;31m"
	local cyan="${esc}1;36m"
	local reset="${esc}0m"
	status=0
	cat <<EOF | expect -f - || status=$?
			spawn "$HOMESHICK_DIR/bin/homeshick" pull --batch "$castle"
			expect -ex "${cyan}         pull${reset} $castle\r${red}         pull${reset} $castle\r
${red}        error${reset} Unable to pull $HOME/.homesick/repos/$castle. Git says:\r
fatal: Not possible to fast-forward, aborting.\r\n" {} default {exit 1}
			# if there is any other output left, then fail
			expect eof {} "?" {exit 1} default {exit 1}
			catch wait result
			exit [lindex \$result 3]
EOF
	[ $status -eq 70 ] # EX_SOFTWARE
	assert_tag_is_removed "$castle"
	[ ! -e "$HOME/.gitignore" ]
}

@test 'pull a castle where the marker tag already exists' {
	local castle=rc-files
	castle "$castle"
	local tag_before tag_after
	tag_before=$(cd "$HOME/.homesick/repos/$castle" &&
		git reset --hard HEAD~1 >/dev/null &&
		git tag "$BEFORE_PULL_TAG" HEAD^ >/dev/null &&
		git rev-parse "$BEFORE_PULL_TAG"
	)

	[ ! -e "$HOME/.gitignore" ]
	local open_bracket="\\u005b"
	local close_bracket="\\u005d"
	local esc="\\u001b$open_bracket"
	local red="${esc}1;31m"
	local cyan="${esc}1;36m"
	local reset="${esc}0m"
	status=0
	cat <<EOF | expect -d -f - || status=$?
			spawn "$HOMESHICK_DIR/bin/homeshick" pull --batch "$castle"
			expect -ex "${cyan}         pull${reset} $castle\r${red}         pull${reset} $castle\r
${red}        error${reset} Pull marker tag ($BEFORE_PULL_TAG) already exists in $HOME/.homesick/repos/$castle. Please resolve this before pulling.\r\n" {} default {exit 1}
			# if there is any other output left, then fail
			expect eof {} "?" {exit 1} default {exit 1}
			catch wait result
			exit [lindex \$result 3]
EOF
	[ $status -eq 64 ] # EX_USAGE
	[ ! -e "$HOME/.gitignore" ]
	# tag should not be touched
	tag_after=$(cd "$HOME/.homesick/repos/$castle" && git rev-parse "$BEFORE_PULL_TAG")
	[ "$tag_before" == "$tag_after" ]
}

# the following 8 tests test some of the various ways a git repo can handle
# merges when pulling.
@test 'pull with local commits and no new files, merge' {
	local castle=pull-test
	castle "$castle"
	reset_and_add_new_file HEAD~1
	(cd "$HOME/.homesick/repos/$castle" && git config pull.rebase false)

	expect_no_new_files "$castle"
}

@test 'pull with local commits and no new files, rebase' {
	local castle=pull-test
	castle "$castle"
	reset_and_add_new_file HEAD~1
	(cd "$HOME/.homesick/repos/$castle" && git config pull.rebase true)

	expect_no_new_files "$castle"
}

@test 'pull with local commits and new files, merge' {
	local castle=pull-test
	castle "$castle"
	reset_and_add_new_file HEAD~2
	(cd "$HOME/.homesick/repos/$castle" && git config pull.rebase false)

	[ ! -e "$HOME/.gitignore" ]
	expect_new_files "$castle" .gitignore
	[ -f "$HOME/.gitignore" ]
}

@test 'pull with local commits and new files, rebase' {
	local castle=pull-test
	castle "$castle"
	reset_and_add_new_file HEAD~2
	(cd "$HOME/.homesick/repos/$castle" && git config pull.rebase true)

	[ ! -e "$HOME/.gitignore" ]
	expect_new_files "$castle" .gitignore
	[ -f "$HOME/.gitignore" ]
}

@test 'pull with local commits and no new files, merge, ff-only' {
	local castle=pull-test
	castle "$castle"
	reset_and_add_new_file HEAD~1
	(cd "$HOME/.homesick/repos/$castle" && git config pull.rebase false && git config pull.ff only)

	# git pull should fail, since the local branch can't be fast-forwarded
	run homeshick pull --batch "$castle"
	[ $status -eq 70 ] # EX_SOFTWARE
	assert_tag_is_removed "$castle"
}

@test 'pull with local commits and no new files, rebase, ff-only' {
	local castle=pull-test
	castle "$castle"
	reset_and_add_new_file HEAD~1
	(cd "$HOME/.homesick/repos/$castle" && git config pull.rebase true && git config pull.ff only)

	expect_no_new_files "$castle"
}

@test 'pull with local commits and new files, merge, ff-only' {
	local castle=pull-test
	castle "$castle"
	reset_and_add_new_file HEAD~2
	(cd "$HOME/.homesick/repos/$castle" && git config pull.rebase false && git config pull.ff only)

	# git pull should fail, since the local branch can't be fast-forwarded
	run homeshick pull --batch "$castle"
	[ $status -eq 70 ] # EX_SOFTWARE
	assert_tag_is_removed "$castle"
}

@test 'pull with local commits and new files, rebase, ff-only' {
	local castle=pull-test
	castle "$castle"
	reset_and_add_new_file HEAD~2
	(cd "$HOME/.homesick/repos/$castle" && git config pull.rebase true && git config pull.ff only)

	[ ! -e "$HOME/.gitignore" ]
	expect_new_files "$castle" .gitignore
	[ -f "$HOME/.gitignore" ]
}
