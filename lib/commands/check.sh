#!/bin/bash

function check {
	local exit_status=$EX_SUCCESS
	[[ ! $1 ]] && help_err check
	local castle=$1
	# repos is a global variable
	# shellcheck disable=SC2154
	local repo="$repos/$castle"
	pending 'checking' "$castle"
	castle_exists 'check' "$castle"

	local ref
	local branch
	# Fetch the current branch name
	ref=$(cd "$repo" && git symbolic-ref HEAD 2>/dev/null)
	branch=${ref#refs/heads/}
	# Get the upstream remote of that branch
	local remote_name
	local remote_url
	remote_name=$(cd "$repo" && git config "branch.$branch.remote" 2>/dev/null)
	remote_url=$(cd "$repo" && git config "remote.$remote_name.url" 2>/dev/null)
	# Get the HEAD of the current branch on the upstream remote
	local remote_head
	remote_head=$(git ls-remote --heads "$remote_url" "$branch" 2>/dev/null | cut -f 1)
	if [[ $remote_head ]]; then
		local local_head git_status
		local_head=$(cd "$repo" && git rev-parse HEAD)
		git_status=$(cd "$repo" && git status --porcelain 2>/dev/null)
		if [[ $remote_head == "$local_head" ]]; then
			if [[ -z $git_status ]]; then
				success 'up to date'
				exit_status=$EX_SUCCESS
			else
				fail 'modified'
				exit_status=$EX_MODIFIED
			fi
		else
			local merge_base
			local checked_ref
			merge_base=$(cd "$repo" && git merge-base "$remote_head" "$local_head" 2>/dev/null)
			checked_ref=$(cd "$repo" && git rev-parse --verify "$remote_head" 2>/dev/null)
			# inlining checked_ref result makes the code unreadable
			# shellcheck disable=SC2181
			if [[ $? == 0 && $merge_base != "" && $merge_base == "$checked_ref" ]]; then
				if [[ -z $git_status ]]; then
					fail 'ahead'
				else
					fail 'ahead*'
				fi
				exit_status=$EX_AHEAD
			else
				if [[ -z $git_status ]]; then
					fail 'behind'
				else
					fail 'behind*'
				fi
				exit_status=$EX_BEHIND
			fi
		fi
	else
		ignore 'uncheckable'
		exit_status=$EX_UNAVAILABLE
	fi
	return "$exit_status"
}
