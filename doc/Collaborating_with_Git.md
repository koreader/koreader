# Collaborating with Git

## Basic
If you are new to Git, you might find some of the following resources useful:

* [GitHub's blog post](https://github.com/blog/120-new-to-git)
* <http://try.github.com/>
* <http://sixrevisions.com/resources/git-tutorials-beginners/>
* <http://rogerdudler.github.io/git-guide/>

## How to pull the latest code from the KOReader repository
First you need to add the official repo to your remote repo list:
```bash
git remote add upstream git@github.com:koreader/koreader.git
```

For koreader-base that is:
```bash
git remote add upstream git@github.com:koreader/koreader-base.git
```

You can verify the remote repo is successfully added by using:
```bash
git remote -v show
```

Now you can pull the latest development code:
```bash
git pull upstream master
```

If you've made some local changes, you'll often want to rebase your local commits on top of the most recent upstream:
```bash
git pull -r upstream master
```
You might want to test that in a new branch first.

## Getting the latest patches from other developer's branch
First you need to add their own repo to your remote repo list:
```bash
git remote add NAME REPO_ADDR
```
Where `NAME` is the alias name you want to give for the remote repo, for example:
```bash
git remote add dpavlin git://github.com/dpavlin/kindlepdfviewer.git
```

You can verify the remote repo was successfully added by using:
```bash
git remote -v show
```

Now you can merge their branch to your local branch. But before you do this, I recommend you create a new branch first and do experimental stuff on top of the new branch so you won't mess with the master branch:
```bash
git checkout -b NEW_TEST_BRANCH_NAME
git pull dpavlin REMOTE_BRANCH_NAME
```

## Quickly testing a patch from a PR
The following example is not directly related to Git, but exclusive to GitHub, although Bitbucket, GitLab etc. tend to provide similar mechanisms.

First, you have to figure out the PR number. It'll be prominently listed on the PR page as well as in the URL. As an example, we'll take `#6282`. Now you can fetch and checkout that code using the GitHub-specific reference:
```bash
git fetch upstream pull/6282/head
git checkout FETCH_HEAD
```

Once you've finished testing, you can just `git checkout master` and it'll be as if nothing ever happened.

## Submitting code change
How to submit my change on top of current development (which is master branch at origin).

This assumes that your repository clone have `origin` which points to upstream official repository as shown below. If you did checkout from your forked copy, and origin points to your local fork, you can always add another remote and replace `origin` in this instructions with another remote name.

```
dpavlin$ git remote -v | grep origin
origin  git@github.com:koreader/koreader.git (fetch)
origin  git@github.com:koreader/koreader.git (push)
dpavlin$ git fetch origin
dpavlin$ git checkout -b issue-235-toc-position origin/master
M       djvulibre
M       kpvcrlib/crengine
M       mupdf
Branch issue-235-toc-position set up to track remote branch master from origin.
Switched to a new branch 'issue-235-toc-position'
```

integrate changes from this issue (or diff, patch, git cherry-pick sha-commit)

```
dpavlin$ git add -p unireader.lua
```
interactively select just changes which are not whitespace

```
dpavlin$ git commit --author NuPogodi -m 'TOC position on current place in the tree #235'
[issue-235-toc-position 25edd31] TOC position on current place in the tree #235
 Author: NuPogodi <surzh@mail.ru>
 1 file changed, 9 insertions(+), 5 deletions(-)
dpavlin$ git show
```

verify that commit looks sane, if I wasn't happy I would do `git --commit --amend`

```
dpavlin$ git push dpavlin issue-235-toc-position
Counting objects: 5, done.
Delta compression using up to 2 threads.
Compressing objects: 100% (3/3), done.
Writing objects: 100% (3/3), 489 bytes, done.
Total 3 (delta 2), reused 0 (delta 0)
To git@github.com:dpavlin/koreader.git
 * [new branch]      issue-235-toc-position -> issue-235-toc-position
```

This assumes that your copy of github source is named `dpavlin` as here:

```
dpavlin$ git remote -v | grep dpavlin
dpavlin git@github.com:dpavlin/koreader.git (fetch)
dpavlin git@github.com:dpavlin/koreader.git (push)
```

Go to your github page and issue pull request
