#!/bin/sh
for name in *.d ; do
    dub $name
done
