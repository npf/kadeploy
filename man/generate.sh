#!/bin/bash

DESTDIR=$1
MANKINDS="1"
DB2MAN=""

#Fedora, Centos
which db2x_docbook2man &>/dev/null && DB2MAN=`which db2x_docbook2man`
#Debian, Ubuntu
which docbook2x-man &>/dev/null && DB2MAN=`which docbook2x-man`

[ ! -n "$DB2MAN" ] && echo "Cannot find the docbook2man command" && exit 1

for kind in $MANKINDS
do
    SUBDIR="man"$kind
    mkdir -p $DESTDIR/$SUBDIR
    for file in $SUBDIR/*.xml
    do
	$DB2MAN $file
	dest_file=`echo $file | sed -e "s/$SUBDIR\///" -e "s/.xml//"`
	mv $dest_file.$kind $DESTDIR/$SUBDIR/
    done
done