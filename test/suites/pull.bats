#!/usr/bin/env bats

load ../helper

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
	local open_bracket="\\u005b"
	local close_bracket="\\u005d"
	local esc="\\u001b$open_bracket"
	local green="${esc}1;32m"
	local cyan="${esc}1;36m"
	local white="${esc}1;37m"
	local reset="${esc}0m"
	cat <<EOF | expect -f -
			spawn "$HOMESHICK_DIR/bin/homeshick" pull "$1"
			expect -ex "${cyan}         pull${reset} $1\r${green}         pull${reset} $1\r
${white}      updates${reset} The castle $1 has new files.\r
${cyan}     symlink?${reset} ${open_bracket}yN${close_bracket} " {} default {exit 1}
			send "y\n"
			expect -ex "y\r${green}     symlink?${reset} ${open_bracket}yN${close_bracket} \r
${cyan}      symlink${reset} .gitignore\r${green}      symlink${reset} .gitignore\r\n" {} default {exit 1}
			expect eof {} "?" {exit 1} default {exit 1}
EOF
}

expect_no_new_files() {
	local open_bracket="\\u005b"
	local close_bracket="\\u005d"
	local esc="\\u001b$open_bracket"
	local green="${esc}1;32m"
	local cyan="${esc}1;36m"
	local reset="${esc}0m"
	cat <<EOF | expect -f -
			spawn "$HOMESHICK_DIR/bin/homeshick" pull --batch "$1"
			expect -ex "${cyan}         pull${reset} $1\r${green}         pull${reset} $1\r\n" {} default {exit 1}
			# if there is any other output left, then fail
			expect eof {} "?" {exit 1} default {exit 1}
EOF
}

@test 'pull skips castles with no upstream remote' {
	castle 'rc-files'
	castle 'dotfiles'
	# The dotfiles FETCH_HEAD should not exist after cloning
	[ ! -e "$HOMESICK/repos/dotfiles/.git/FETCH_HEAD" ]
	(cd "$HOMESICK/repos/rc-files" && git remote rm origin)
	run "$HOMESHICK_FN" pull rc-files dotfiles
	[ $status -eq 0 ] # EX_SUCCESS
	# dotfiles FETCH_HEAD should exist if the castle was pulled
	[ -e "$HOMESICK/repos/dotfiles/.git/FETCH_HEAD" ]
}

@test 'pull prompts for symlinking if new files are present' {
	castle 'rc-files'
	(cd "$HOME/.homesick/repos/rc-files" && git reset --hard HEAD~1 >/dev/null)
	homeshick link --batch --quiet rc-files

	[ ! -e "$HOME/.gitignore" ]
	expect_new_files rc-files
	[ -f "$HOME/.gitignore" ]
}

@test 'pull after symlinking new files' {
	castle 'rc-files'
	(cd "$HOME/.homesick/repos/rc-files" && git reset --hard HEAD~1 >/dev/null)
	homeshick link --batch --quiet rc-files
	homeshick pull --batch --force rc-files

	expect_no_new_files rc-files
}

@test 'pull with no new files present' {
	castle 'pull-test'
	(cd "$HOME/.homesick/repos/pull-test" && git reset --hard HEAD~1 >/dev/null)

	expect_no_new_files pull-test
}

@test 'pull with local commits and no new files, merge' {
	castle 'pull-test'
	reset_and_add_new_file HEAD~1
	(cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase false)

	expect_no_new_files pull-test
}

@test 'pull with local commits and no new files, rebase' {
	castle 'pull-test'
	reset_and_add_new_file HEAD~1
	(cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase true)

	expect_no_new_files pull-test
}

@test 'pull with local commits and new files, merge' {
	castle 'pull-test'
	reset_and_add_new_file HEAD~2
	(cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase false)

	[ ! -e "$HOME/.gitignore" ]
	expect_new_files pull-test
	[ -f "$HOME/.gitignore" ]
}

@test 'pull with local commits and new files, rebase' {
	castle 'pull-test'
	reset_and_add_new_file HEAD~2
	(cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase true)

	[ ! -e "$HOME/.gitignore" ]
	expect_new_files pull-test
	[ -f "$HOME/.gitignore" ]
}

@test 'pull with local commits, fast-forward only' {
	castle 'pull-test'
	reset_and_add_new_file HEAD~2
	(cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase false && git config pull.ff only)

	# git pull should fail, since the local branch can't be fast-forwarded
	run homeshick pull --batch pull-test
	[ $status -eq 70 ] # EX_SOFTWARE
}

@test "pull skips symlinking if git fails" {
	castle 'pull-test'
	reset_and_add_new_file HEAD~2
	(cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase false && git config pull.ff only)

	run homeshick pull --batch pull-test
	local open_bracket="\\u005b"
	local close_bracket="\\u005d"
	local esc="\\u001b$open_bracket"
	local red="${esc}1;31m"
	local cyan="${esc}1;36m"
	local reset="${esc}0m"
	cat <<EOF | expect -f -
			spawn "$HOMESHICK_DIR/bin/homeshick" pull --batch pull-test
			expect -ex "${cyan}         pull${reset} pull-test\r${red}         pull${reset} pull-test\r
${red}        error${reset} Unable to pull $HOME/.homesick/repos/pull-test. Git says:\r
fatal: Not possible to fast-forward, aborting.\r\n" {} default {exit 1}
			# if there is any other output left, then fail
			expect eof {} "?" {exit 1} default {exit 1}
EOF
}
