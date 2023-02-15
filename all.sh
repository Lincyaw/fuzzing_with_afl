#!/bin/zsh
cd ~/work
rm -rf objdump/perf-data
mkdir objdump/perf-data

# use perf to profile data
bash run.sh ./objdump/perf-data "/home/nn/binutils-gdb/binutils/objdump -d" /home/nn/work/objdump/oriafl-oribin/master/queue > log

# transform the format to bolt
rm -rf objdump/combined-data
mkdir objdump/combined-data
bash transform.sh objdump/perf-data/ objdump/combined-data /home/nn/binutils-gdb/binutils/objdump

# merge bolt format
merge-fdata objdump/combined-data/* > combined.data

# change the binary
llvm-bolt /home/nn/binutils-gdb/binutils/objdump -o /home/nn/binutils-gdb/binutils/objdump.bolt -data=all.data  -reorder-blocks=ext-tsp -reorder-functions=hfsort -split-functions -split-all-cold -split-eh -dyno-stats

