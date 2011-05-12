#!/bin/sh
echo 'Iniciando deployment'
export target='../deployment/ticket-checkin'
mv $target'/.git' $target'/.git_tmp'
cp -R ./ $target
rm -rf $target'/.git'
mv $target'/.git_tmp' $target'/.git'
rm $target'/.gitignore'
rm $target/'Gemfile'
rm $target/'Gemfile.lock'
cd $target
ls -la
git add .
git commit -m 'deploy'
git push -f origin master

