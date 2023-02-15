# compile program using afl-clang-lto and allow relocation
cd /home/nn/Fuzzing_libxml2/libxml2-2.9.4
# CC=~/AFL-Ori/afl-clang-lto CXX=~/AFL-Ori/afl-clang-lto++  CFLAGS='-fprofile-arcs -ftest-coverage' CXXFLAGS='-fprofile-arcs -ftest-coverage' LDFLAGS='-Wl,--emit-relocs -fprofile-arcs -ftest-coverage' ./configure --prefix="$HOME/Fuzzing_libxml2/libxml2-2.9.4/install" --disable-shared --without-debug --without-ftp --without-http --without-legacy --without-python LIBS='-ldl'
CC=~/AFL-Ori/afl-clang-lto CXX=~/AFL-Ori/afl-clang-lto++  CFLAGS='-fprofile-instr-generate -fcoverage-mapping' CXXFLAGS='-fprofile-instr-generate -fcoverage-mapping' LDFLAGS='-Wl,--emit-relocs' ./configure --prefix="$HOME/Fuzzing_libxml2/libxml2-2.9.4/install" --disable-shared --without-debug --without-ftp --without-http --without-legacy --without-python LIBS='-ldl'
# CC=~/AFL-Ori/afl-clang-lto CXX=~/AFL-Ori/afl-clang-lto++ LDFLAGS='-Wl,--emit-relocs -fprofile-arcs -ftest-coverage' ./configure --prefix="$HOME/Fuzzing_libxml2/libxml2-2.9.4/install" --disable-shared --without-debug --without-ftp --without-http --without-legacy --without-python LIBS='-ldl'


CC=~/AFL-Modify/afl-clang-lto CXX=~/AFL-Modify/afl-clang-lto++  CFLAGS='-fprofile-instr-generate -fcoverage-mapping' CXXFLAGS='-fprofile-instr-generate -fcoverage-mapping' LDFLAGS='-Wl,--emit-relocs' ./configure --prefix='/home/nn/binutils-gdb/install' --disable-shared 


make -j16

# copy binary to testing dir
cp /home/nn/Fuzzing_libxml2/libxml2-2.9.4/xmllint /home/nn/work/xml2/bin