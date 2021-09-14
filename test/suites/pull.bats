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

BEFORE_PULL_TAG=__homeshick-before-pull__
assert_tag_is_removed() {
  for castle in "$@"; do
    (
      cd "$HOME/.homesick/repos/$castle" || return $?
      # show all the tags if the test fails
      git show-ref --tags >&2 || true
      # this tag should not exist
      run git rev-parse --verify "refs/tags/$BEFORE_PULL_TAG" >&2 2>&-
      assert_failure
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
  # takes castle name as first argument, and new files as remaining arguments
  local castle="$1"
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
  local castle="$1"
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
  assert_tag_is_removed rc-files dotfiles
  # dotfiles FETCH_HEAD should exist if the castle was pulled
  [ -e "$HOME/.homesick/repos/dotfiles/.git/FETCH_HEAD" ]
}

@test 'pull prompts for symlinking if new files are present' {
  local castle=rc-files
  castle "$castle"
  (cd "$HOME/.homesick/repos/$castle" && git reset --hard HEAD~1 >/dev/null)
  homeshick link --batch --quiet "$castle"

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull "$castle" <<<y
  assert_success
  assert_tag_is_removed "$castle"
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
  run homeshick pull "$castle" <<<y
  assert_success
  assert_tag_is_removed "$castle"
  expect_new_files "$castle" .bashrc
  [ -f "$HOME/.bashrc" ]
}

@test 'pull with no new files present' {
  local castle=pull-test
  castle "$castle"
  (cd "$HOME/.homesick/repos/$castle" && git reset --hard HEAD~1 >/dev/null)

  run homeshick pull --batch "$castle"
  assert_success
  assert_tag_is_removed "$castle"
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

  run homeshick pull --batch "$castle"
  assert_success
  assert_tag_is_removed "$castle"
  expect_no_new_files "$castle"
}

@test 'pull a castle with a git conflict' {
  local castle=pull-test
  castle "$castle"
  reset_and_add_new_file HEAD~2
  (cd "$HOME/.homesick/repos/$castle" && git config pull.rebase false && git config pull.ff only)

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull --batch "$castle"
  assert_failure 70 # EX_SOFTWARE
  assert_tag_is_removed "$castle"
  [ ! -e "$HOME/.gitignore" ]
  local red='\e[1;31m'
  local cyan='\e[1;36m'
  local reset='\e[0m'
  {
    echo -ne "$cyan         pull$reset $castle\r"
    echo -ne  "$red         pull$reset $castle\n"
    echo -ne  "$red        error$reset Unable to pull $HOME/.homesick/repos/$castle. Git says:"
  } | assert_output -p -
}

@test 'pull a castle where the marker tag already exists' {
  local castle=rc-files
  castle "$castle"
  local tag_before tag_after
  tag_before=$(cd "$HOME/.homesick/repos/$castle" &&
    git reset --hard HEAD~1 >/dev/null &&
    git tag "$BEFORE_PULL_TAG" HEAD^ &&
    git rev-parse "$BEFORE_PULL_TAG"
  )

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull --batch "$castle"
  assert_failure 64 # EX_USAGE
  # tag should not be touched
  tag_after=$(cd "$HOME/.homesick/repos/$castle" && git rev-parse "$BEFORE_PULL_TAG")
  [ "$tag_before" == "$tag_after" ]
  [ ! -e "$HOME/.gitignore" ]

  local red='\e[1;31m'
  local cyan='\e[1;36m'
  local reset='\e[0m'
  {
    echo -ne "$cyan         pull$reset $castle\r"
    echo -ne  "$red         pull$reset $castle\n"
    echo -ne  "$red        error$reset Pull marker tag ($BEFORE_PULL_TAG) already exists in $HOME/.homesick/repos/$castle. Please resolve this before pulling."
  } | assert_output -
}

# the following 8 tests test some of the various ways a git repo can handle
# merges when pulling.
@test 'pull with local commits and no new files, merge' {
  local castle=pull-test
  castle "$castle"
  reset_and_add_new_file HEAD~1
  (cd "$HOME/.homesick/repos/$castle" && git config pull.rebase false)

  run homeshick pull --batch "$castle"
  assert_success
  assert_tag_is_removed "$castle"
  expect_no_new_files "$castle"
}

@test 'pull with local commits and no new files, rebase' {
  local castle=pull-test
  castle "$castle"
  reset_and_add_new_file HEAD~1
  (cd "$HOME/.homesick/repos/$castle" && git config pull.rebase true)

  run homeshick pull --batch "$castle"
  assert_success
  assert_tag_is_removed "$castle"
  expect_no_new_files "$castle"
}

@test 'pull with local commits and new files, merge' {
  local castle=pull-test
  castle "$castle"
  reset_and_add_new_file HEAD~2
  (cd "$HOME/.homesick/repos/$castle" && git config pull.rebase false)

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull "$castle" <<<y
  assert_success
  assert_tag_is_removed "$castle"
  expect_new_files "$castle" .gitignore
  [ -f "$HOME/.gitignore" ]
}

@test 'pull with local commits and new files, rebase' {
  local castle=pull-test
  castle "$castle"
  reset_and_add_new_file HEAD~2
  (cd "$HOME/.homesick/repos/$castle" && git config pull.rebase true)

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull "$castle" <<<y
  assert_success
  assert_tag_is_removed "$castle"
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
  assert_failure 70 # EX_SOFTWARE
  assert_tag_is_removed "$castle"
}

@test 'pull with local commits and no new files, rebase, ff-only' {
  local castle=pull-test
  castle "$castle"
  reset_and_add_new_file HEAD~1
  (cd "$HOME/.homesick/repos/$castle" && git config pull.rebase true && git config pull.ff only)

  run homeshick pull --batch "$castle"
  assert_success
  assert_tag_is_removed "$castle"
  expect_no_new_files "$castle"
}

@test 'pull with local commits and new files, merge, ff-only' {
  local castle=pull-test
  castle "$castle"
  reset_and_add_new_file HEAD~2
  (cd "$HOME/.homesick/repos/$castle" && git config pull.rebase false && git config pull.ff only)

  # git pull should fail, since the local branch can't be fast-forwarded
  run homeshick pull --batch "$castle"
  assert_failure 70 # EX_SOFTWARE
  assert_tag_is_removed "$castle"
}

@test 'pull with local commits and new files, rebase, ff-only' {
  local castle=pull-test
  castle "$castle"
  reset_and_add_new_file HEAD~2
  (cd "$HOME/.homesick/repos/$castle" && git config pull.rebase true && git config pull.ff only)

  [ ! -e "$HOME/.gitignore" ]
  run homeshick pull "$castle" <<<y
  assert_success
  assert_tag_is_removed "$castle"
  expect_new_files "$castle" .gitignore
  [ -f "$HOME/.gitignore" ]
}
