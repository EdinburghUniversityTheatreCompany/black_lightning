#!/usr/bin/env bash

if [ $# -lt 1 ] ; then
    echo "Usage:   " $0 " <start | stop> "
    exit 1
fi

action=$1

export RAILS_ENV=production

#script_location=$(cd ${0%/*} && pwd -P)
#cd $script_location/..
#rails_root=`pwd`

if [ -f "/etc/profile" ]; then
  . /etc/profile
fi

logfile=/var/www/bedlamtheatre_co_uk/current/log/delayed_job.log
echo "-----------------------------------------------" >> $logfile 2>&1
cho "Running bundle exec ./script/delayed_job $action" >> $logfile 2>&1
echo `date` >> $logfile 2>&1
echo `env` >> $logfile 2>&1

bundle exec /var/www/bedlamtheatre_co_uk/current/script/delayed_job $action >> $logfile 2>&1

