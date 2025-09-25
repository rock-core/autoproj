#!/bin/sh

set -e

sudo gem install bundler

bundle config set path vendor/bundle
bundle config set with dev:vscode
bundle install