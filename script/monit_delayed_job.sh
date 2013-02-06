#!/usr/bin/env bash

if [ $# -lt 1 ] ; then
    echo "Usage:   " $0 " <start | stop> "
    exit 1
fi

action=$1

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games
export RAILS_ENV=production
export GEM_PATH="/var/www/bedlamtheatre_co_uk/gems"
export GEM_HOME="/var/www/bedlamtheatre_co_uk/gems"

cd /var/www/bedlamtheatre_co_uk/current

/var/www/bedlamtheatre_co_uk/gems/bin/bundle exec /var/www/bedlamtheatre_co_uk/current/script/delayed_job $action

