#!/usr/bin/env bats

load ../helper.sh

setup() {
  create_test_dir
  # shellcheck source=../../homeshick.sh
  source "$HOMESHICK_DIR/homeshick.sh"
}

teardown() {
  delete_test_dir
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
  # takes castle name as first argument, and new files as remaining arguments
  castle="$1"
  shift
  run homeshick pull "$castle" <<<y
  local green=$'\e[1;32m'
  local cyan=$'\e[1;36m'
  local white=$'\e[1;37m'
  local reset=$'\e[0m'
  local cr=$'\r'
  assert_line  "${cyan}         pull${reset} $castle${cr}${green}         pull${reset} $castle"
  assert_line "${white}      updates${reset} The castle $castle has new files."
  assert_line  "${cyan}     symlink?${reset} [yN] y${cr}${green}     symlink?${reset} [yN] "
  for file in "$@"; do
    assert_line  "${cyan}      symlink${reset} $file${cr}${green}      symlink${reset} $file"
  done
}

expect_no_new_files() {
  # takes castle name as first argument
  castle="$1"
  shift
  run homeshick pull --batch "$castle"
  local green=$'\e[1;32m'
  local cyan=$'\e[1;36m'
  local reset=$'\e[0m'
  assert_output "${cyan}         pull${reset} $castle"$'\r'"${green}         pull${reset} $castle"
}

@test 'pull skips castles with no upstream remote' {
  castle 'rc-files'
  castle 'dotfiles'
  # The dotfiles FETCH_HEAD should not exist after cloning
  [ ! -e "$HOME/.homesick/repos/dotfiles/.git/FETCH_HEAD" ]
  (cd "$HOME/.homesick/repos/rc-files" && git remote rm origin)
  run homeshick pull rc-files dotfiles
  [ $status -eq 0 ] # EX_SUCCESS
  # dotfiles FETCH_HEAD should exist if the castle was pulled
  [ -e "$HOME/.homesick/repos/dotfiles/.git/FETCH_HEAD" ]
}

@test 'pull prompts for symlinking if new files are present' {
  castle 'rc-files'
  (cd "$HOME/.homesick/repos/rc-files" && git reset --hard HEAD~1 >/dev/null)
  homeshick link --batch --quiet rc-files

  [ ! -e "$HOME/.gitignore" ]
  expect_new_files rc-files .gitignore
  [ -f "$HOME/.gitignore" ]
}

@test 'pull prompts for symlinking with renamed files' {
  castle 'pull-renamed'
  # reset to before .bashrc-wrong-name was renamed to .bashrc
  (cd "$HOME/.homesick/repos/pull-renamed" && git reset --hard HEAD~2 >/dev/null)
  homeshick link --batch --quiet pull-renamed

  [ ! -e "$HOME/.bashrc" ]
  expect_new_files pull-renamed .bashrc
  [ -f "$HOME/.bashrc" ]
}

@test 'pull with no new files present' {
  castle 'pull-test'
  (cd "$HOME/.homesick/repos/pull-test" && git reset --hard HEAD~1 >/dev/null)

  expect_no_new_files pull-test
}

@test 'pull after symlinking new files' {
  castle 'rc-files'
  (cd "$HOME/.homesick/repos/rc-files" && git reset --hard HEAD~1 >/dev/null)
  homeshick link --batch --quiet rc-files
  homeshick pull --batch --force rc-files

  expect_no_new_files rc-files
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
  expect_new_files pull-test .gitignore
  [ -f "$HOME/.gitignore" ]
}

@test 'pull with local commits and new files, rebase' {
  castle 'pull-test'
  reset_and_add_new_file HEAD~2
  (cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase true)

  [ ! -e "$HOME/.gitignore" ]
  expect_new_files pull-test .gitignore
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
  local red=$'\e[1;31m'
  local cyan=$'\e[1;36m'
  local reset=$'\e[0m'
  assert_line "${cyan}         pull${reset} pull-test"$'\r'"${red}         pull${reset} pull-test"
  assert_line  "${red}        error${reset} Unable to pull $HOME/.homesick/repos/pull-test. Git says:"
  assert_line "fatal: Not possible to fast-forward, aborting."
}
