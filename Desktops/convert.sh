#!/bin/sh

for i in $(ls original/*.*); do 
	convert $i -resize 320x240 -depth 16 -gravity Center -extent 320x240 320x212x16/$i.png 
done
