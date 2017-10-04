#!/usr/bin/env bash

if [ $# -lt 1 ] ; then
    echo "Usage:   " $0 " <start | stop | restart> "
    exit 1
fi

action=$1

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games
export RAILS_ENV=production
export GEM_PATH="/srv/black_lightning/current/gems"
export GEM_HOME="/srv/black_lightning/current/gems"

cd /srv/black_lightning/current

bundle exec script/delayed_job $action

