#!/bin/sh
for name in *.d ; do
    dub $name || exit 1
done

