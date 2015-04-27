#!/bin/sh

for i in $(ls *.png); do 
	convert -depth 16 $i ../$i 
done
