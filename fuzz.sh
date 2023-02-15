#!/bin/zsh
cd /home/nn/binutils-gdb/binutils
rm -rf /home/nn/binutils-gdb/binutilsafl_out/
# fuzzing it
export LLVM_PROFILE_FILE="/home/nn/work/objdump/coverage.oriafl.oribin.profraw"
/home/nn/AFL-Modify/afl-fuzz -m none -i /home/nn/work/objdump/afl_in -o /home/nn/work/objdump/oriafl-oribin -s 123 -D -M master -- $1 -d @@

