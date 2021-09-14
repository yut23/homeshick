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

backdate_git_operations() {
  # This function changes the time of all git operations in the current
  # subshell to be several (first argument, defaults to 5) seconds in the past.
  offset=${1:-5}
  local timestamp
  timestamp=$(( $(date +%s) - offset ))
  # this is what is usually displayed by git log
  export GIT_AUTHOR_DATE="@$timestamp"
  # this is what most git commands actually care about (like @{1 second ago})
  export GIT_COMMITTER_DATE="@$timestamp"
}

reset_and_add_new_file() {
  (
    backdate_git_operations 3
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
  local green='\e[1;32m'
  local cyan='\e[1;36m'
  local white='\e[1;37m'
  local reset='\e[0m'
  # these variables are intended to be parsed by printf
  # shellcheck disable=SC2059
  {
    printf  "$cyan         pull$reset %s\r" "$castle"
    printf "$green         pull$reset %s\n" "$castle"
    printf "$white      updates$reset The castle %s has new files.\n" "$castle"
    printf  "$cyan     symlink?$reset [yN] y\r"
    printf "$green     symlink?$reset [yN] \n"
    for file in "$@"; do
    printf  "$cyan      symlink$reset %s\r" "$file"
    printf "$green      symlink$reset %s\n" "$file"
    done
  } | assert_output -
}

expect_no_new_files() {
  # takes castle name as first argument
  castle="$1"
  shift
  local green='\e[1;32m'
  local cyan='\e[1;36m'
  local reset='\e[0m'
  {
    printf  "$cyan         pull$reset %s\r" "$castle"
    printf "$green         pull$reset %s\n" "$castle"
  } | assert_output -
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
  (
    # make these operations happen several seconds in the past, so that
    # symlink_new_files can tell what commits are new
    backdate_git_operations
    castle 'rc-files'
    (cd "$HOME/.homesick/repos/rc-files" && git reset --hard HEAD~1 >/dev/null)
    homeshick link --batch --quiet rc-files
  )

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull rc-files <<<y
  assert_success
  expect_new_files rc-files .gitignore
  [ -f "$HOME/.gitignore" ]
}

@test 'pull prompts for symlinking with renamed files' {
  (
    backdate_git_operations
    castle 'pull-renamed'
    # reset to before .bashrc-wrong-name was renamed to .bashrc
    (cd "$HOME/.homesick/repos/pull-renamed" && git reset --hard HEAD~2 >/dev/null)
    homeshick link --batch --quiet pull-renamed
  )

  [ ! -e "$HOME/.bashrc" ]
  run homeshick pull pull-renamed <<<y
  assert_success
  expect_new_files pull-renamed .bashrc
  [ -f "$HOME/.bashrc" ]
}

@test 'pull with no new files present' {
  (
    backdate_git_operations
    castle 'pull-test'
    (cd "$HOME/.homesick/repos/pull-test" && git reset --hard HEAD~1 >/dev/null)
  )

  run homeshick pull --batch pull-test
  assert_success
  expect_no_new_files pull-test
}

@test 'pull after symlinking new files' {
  # this checks that we don't try to link files again if the last operation was
  # a pull
  (
    backdate_git_operations
    castle 'rc-files'
    (cd "$HOME/.homesick/repos/rc-files" && git reset --hard HEAD~1 >/dev/null)
    homeshick link --batch --quiet rc-files
    backdate_git_operations 3
    homeshick pull --batch --force rc-files
  )

  run homeshick pull --batch rc-files
  assert_success
  expect_no_new_files rc-files
}

@test 'pull with local commits and no new files, merge' {
  (
    backdate_git_operations
    castle 'pull-test'
    reset_and_add_new_file HEAD~1
    (cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase false)
  )

  run homeshick pull --batch pull-test
  assert_success
  expect_no_new_files pull-test
}

@test 'pull with local commits and no new files, rebase' {
  (
    backdate_git_operations
    castle 'pull-test'
    reset_and_add_new_file HEAD~1
    (cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase true)
  )

  run homeshick pull --batch pull-test
  assert_success
  expect_no_new_files pull-test
}

@test 'pull with local commits and new files, merge' {
  (
    backdate_git_operations
    castle 'pull-test'
    reset_and_add_new_file HEAD~2
    (cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase false)
  )

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull pull-test <<<y
  assert_success
  expect_new_files pull-test .gitignore
  [ -f "$HOME/.gitignore" ]
}

@test 'pull with local commits and new files, rebase' {
  (
    backdate_git_operations
    castle 'pull-test'
    reset_and_add_new_file HEAD~2
    (cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase true)
  )

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull pull-test <<<y
  assert_success
  expect_new_files pull-test .gitignore
  [ -f "$HOME/.gitignore" ]
}

@test 'pull with local commits, fast-forward only, merge' {
  (
    backdate_git_operations
    castle 'pull-test'
    reset_and_add_new_file HEAD~2
    (cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase false && git config pull.ff only)
  )

  # git pull should fail, since the local branch can't be fast-forwarded
  run homeshick pull --batch pull-test
  assert_failure 70 # EX_SOFTWARE
}

@test 'pull with local commits, fast-forward only, rebase' {
  (
    backdate_git_operations
    castle 'pull-test'
    reset_and_add_new_file HEAD~2
    (cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase true && git config pull.ff only)
  )

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull pull-test <<<y
  assert_success
  expect_new_files pull-test .gitignore
  [ -f "$HOME/.gitignore" ]
}

@test "pull skips symlinking if git fails" {
  (
    backdate_git_operations
    castle 'pull-test'
    reset_and_add_new_file HEAD~2
    (cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase false && git config pull.ff only)
  )

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull --batch pull-test
  assert_failure 70 # EX_SOFTWARE
  [ ! -e "$HOME/.gitignore" ]
  local red='\e[1;31m'
  local cyan='\e[1;36m'
  local reset='\e[0m'
  {
    echo -ne "$cyan         pull$reset pull-test\r"
    echo -ne  "$red         pull$reset pull-test\n"
    echo -ne  "$red        error$reset Unable to pull $HOME/.homesick/repos/pull-test. Git says:\n"
    echo "fatal: Not possible to fast-forward, aborting."
  } | assert_output -
}
