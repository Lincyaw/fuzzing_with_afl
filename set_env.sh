#!/bin/bash
command=$1
export SOURCE_CODE_DIR='/home/nn/Fuzzing_libxml2/libxml2-2.9.4'
export MY_AFL_TOOL_PATH='/home/nn/AFL-Ori'
export BASE_WORK_DIR='/home/nn/work/xmllint'
export FUZZING_BIN='xmllint'
export FUZZING_ARGS="--memory --noenc --nocdata --dtdattr --loaddtd --valid --xinclude"
export MY_AFL_SEEDS_IN=$BASE_WORK_DIR/afl_in_seeds
# export MY_AFL_SEEDS_IN='/home/nn/work/seeds/general_evaluation/json'

if [ $ROUND ];then
	echo ""
else
	read -r -p "Please choose ROUND name: 1. ORIGINAL 2. BOLT" input
    
        case $input in
        [1])
            export ROUND="ORIGINAL"
            ;;
        [2])
            export ROUND="BOLT"
            ;;
        *)
        echo "Invalid input..."
        exit 1
        ;;
    esac
fi
echo "================Running in "$ROUND" mode====================="
export OUTPUT_BINARY_PATH=$BASE_WORK_DIR/bin
export LLVM_PROFILE_DIR=$BASE_WORK_DIR/prof
export MY_AFL_OUTPUT_PATH=$BASE_WORK_DIR/afl_out
export PERF_RECORD_DIR=$BASE_WORK_DIR/perf_data
export BOLT_FORMAT_DATA_DIR=$BASE_WORK_DIR/bolt_format_prof
export AFL_LLVM_DOCUMENT_IDS=$BASE_WORK_DIR/afl_ids

export CC=$MY_AFL_TOOL_PATH/afl-clang-lto 
export CXX=$MY_AFL_TOOL_PATH/afl-clang-lto++  
export CFLAGS='-fprofile-instr-generate -fcoverage-mapping' 
export CXXFLAGS='-fprofile-instr-generate -fcoverage-mapping' 
export LDFLAGS='-Wl,--emit-relocs'


compile(){
    cd $SOURCE_CODE_DIR
    if [ -f "$BASE_WORK_DIR/denylist.txt" ]; then
        export AFL_LLVM_DENYLIST=$BASE_WORK_DIR/denylist.txt
        echo "yes"
    fi
    ./configure --disable-shared 
    make clean
    make -j12
    cp ./$1 $OUTPUT_BINARY_PATH/$1.ORIGINAL
}

fuzz(){
    export LLVM_PROFILE_FILE=$LLVM_PROFILE_DIR/$ROUND.profraw
    # echo "$MY_AFL_TOOL_PATH/afl-fuzz -m none -i $MY_AFL_SEEDS_IN -o $MY_AFL_OUTPUT_PATH.$ROUND -s 123 -D -M master -- $OUTPUT_BINARY_PATH/$1.$ROUND $2 @@"
    $MY_AFL_TOOL_PATH/afl-fuzz -m none -i $MY_AFL_SEEDS_IN -o $MY_AFL_OUTPUT_PATH.$ROUND -s 123 -D -M master -- $OUTPUT_BINARY_PATH/$1.$ROUND $2 @@
}

prefuzz(){
    export LLVM_PROFILE_FILE=$LLVM_PROFILE_DIR/$ROUND.profraw
    export AFL_DEBUG=1
    $MY_AFL_TOOL_PATH/afl-fuzz -m none -i $MY_AFL_SEEDS_IN -o $MY_AFL_OUTPUT_PATH.$ROUND -s 123 -x $BASE_WORK_DIR/dictionaries/xml.dict -D -M master -- $OUTPUT_BINARY_PATH/$1.$ROUND $2 @@
}

pro_deny_list(){
    for i in `grep var_bytes $BASE_WORK_DIR/afl_out.$ROUND/master/fuzzer_stats | sed 's/^.*://'`; do
        echo fuck
        egrep "edgeID=$i\$" $BASE_WORK_DIR/afl_ids
    done | awk '{print$2}' | sed 's/Function=/fun: /' | sort -u > $BASE_WORK_DIR/denylist.txt

    # edges=$(cat $BASE_WORK_DIR/afl_out.$ROUND/master/fuzzer_stats| grep var_bytes | awk '{ s = ""; for (i = 3; i <= NF; i++) s = s $i " "; print s }' )
    # lines="="$(eval echo $edges | sed 's/[ ][ ]*/|=/g')
    # grep -E "$lines" $BASE_WORK_DIR/afl_ids | awk '{print $2}' | uniq -u | sed 's/Function=/fun: /g' > $BASE_WORK_DIR/denylist.txt
}

perf_record(){
    outputfiledir=$PERF_RECORD_DIR
    seeddir=$MY_AFL_OUTPUT_PATH.$ROUND/master/queue

    _fifofile="perf.fifo"
    mkfifo $_fifofile     # 创建一个FIFO类型的文件
    exec 6<>$_fifofile    # 将文件描述符6写入 FIFO 管道， 这里6也可以是其它数字
    rm $_fifofile         # 删也可以，

    degree=$(nproc)  # 定义并行度

    #根据并行度设置信号个数
    #事实上是在fd6中放置了$degree个回车符
    for ((i=0;i<${degree};i++));do
        echo
    done >&6

    for i in $seeddir/* 
    do
        # 从管道中读取（消费掉）一个字符信号
        # 当FD6中没有回车符时，停止，实现并行度控制
        read -u6
        {
            cur_timestamp=$(date +%s%N)
            echo "perf record -e cycles:u -j any,u -o $outputfiledir/$cur_timestamp.data -- $OUTPUT_BINARY_PATH/$1.$ROUND $2 $i"
            perf record -e cycles:u -j any,u -o $outputfiledir/$cur_timestamp.data -- $OUTPUT_BINARY_PATH/$1.$ROUND $2 $i
            echo >&6 # 当进程结束以后，再向管道追加一个信号，保持管道中的信号总数量
        } &
    done
    wait # 等待所有任务结束
    exec 6>&- # 关闭管道
}

perf_to_bolt(){
    bin=$1.$ROUND

    _fifofile="afl.fifo"
    mkfifo $_fifofile     # 创建一个FIFO类型的文件
    exec 6<>$_fifofile    # 将文件描述符6写入 FIFO 管道， 这里6也可以是其它数字
    

    degree=$(nproc)  # 定义并行度

    #根据并行度设置信号个数
    #事实上是在fd6中放置了$degree个回车符
    for ((i=0;i<${degree};i++));do
        echo
    done >&6

    for i in $PERF_RECORD_DIR/* 
    do
        # 从管道中读取（消费掉）一个字符信号
        # 当FD6中没有回车符时，停止，实现并行度控制
        read -u6
        {
            cur_timestamp=$(date +%s%N)
            echo "perf2bolt -p $i -o $BOLT_FORMAT_DATA_DIR/$cur_timestamp.fdata $OUTPUT_BINARY_PATH/$bin"
            perf2bolt -p $i -o $BOLT_FORMAT_DATA_DIR/$cur_timestamp.fdata $OUTPUT_BINARY_PATH/$bin
            echo >&6 # 当进程结束以后，再向管道追加一个信号，保持管道中的信号总数量
        } &
    done

    wait # 等待所有任务结束
    exec 6>&- # 关闭管道
    rm $_fifofile         # 删也可
}

merge(){
    # merge bolt format
    rm $BASE_WORK_DIR/combined.data
    find $BASE_WORK_DIR/bolt_format_prof -name "*.fdata" -print0 | xargs -0 merge-fdata -o $BASE_WORK_DIR/combined.data
    # merge-fdata $BOLT_FORMAT_DATA_DIR/* > $BASE_WORK_DIR/combined.data

    # change the binary
    llvm-bolt $OUTPUT_BINARY_PATH/$1.$ROUND -o $OUTPUT_BINARY_PATH/$2 -data=$BASE_WORK_DIR/combined.data  -reorder-blocks=ext-tsp -reorder-functions=hfsort -split-functions -split-all-cold -split-eh -dyno-stats
}

read -r -p "Please choose ROUND name: 
1. reset 
2. compile 
3. fuzz to produce denylist 
4. produce denylist
5. normal fuzz
6. transform data and optimize with bolt
7. perf_record
8. perf2bolt
9. merge
" input
case $input in
[1])
        echo "Please check: "
    echo "1. source code directory is $SOURCE_CODE_DIR"
    echo "2. afl tool chain path is $MY_AFL_TOOL_PATH"
    echo "3. base working directory is $BASE_WORK_DIR"
    echo ""
    echo "The following directory will be created and cleaned if exists"
    echo ""
    echo "1. $OUTPUT_BINARY_PATH"
    echo "2. $LLVM_PROFILE_DIR"
    echo "3. $MY_AFL_SEEDS_IN"
    echo "4. $MY_AFL_OUTPUT_PATH"
    echo "5. $PERF_RECORD_DIR"
    echo "6. $BOLT_FORMAT_DATA_DIR"
    echo ""
    read -r -p "Are You Sure? [Y/n] " input

    case $input in
        [yY][eE][sS]|[yY])
            echo "Yes"
            ;;
        [nN][oO]|[nN])
            echo "No"
            ;;
        *)
        echo "Invalid input..."
        exit 1
        ;;
    esac

    rm -rf $BASE_WORK_DIR
    mkdir $BASE_WORK_DIR
    if [ ! -d $OUTPUT_BINARY_PATH ]; then 
        mkdir $OUTPUT_BINARY_PATH
    fi
    if [ ! -d $LLVM_PROFILE_DIR ]; then 
        mkdir $LLVM_PROFILE_DIR
    fi
    if [ ! -d $MY_AFL_SEEDS_IN ]; then 
        mkdir $MY_AFL_SEEDS_IN
    fi
    if [ ! -d $PERF_RECORD_DIR ]; then 
        mkdir $PERF_RECORD_DIR
    fi
    if [ ! -d $BOLT_FORMAT_DATA_DIR ]; then 
        mkdir $BOLT_FORMAT_DATA_DIR
    fi
    ;;
[2])
    compile $FUZZING_BIN
    ;;
[3])
    prefuzz $FUZZING_BIN "$FUZZING_ARGS"
    ;;
[4])
    pro_deny_list
    ;;
[5])
    fuzz $FUZZING_BIN "$FUZZING_ARGS"
    ;;
[6])
    perf_record $FUZZING_BIN "$FUZZING_ARGS"
    perf_to_bolt $FUZZING_BIN
    merge $FUZZING_BIN $FUZZING_BIN.BOLT
    ;;
[7])
    perf_record $FUZZING_BIN "$FUZZING_ARGS"
    ;;
[8])
    perf_to_bolt $FUZZING_BIN
    ;;
[9])
    merge $FUZZING_BIN $FUZZING_BIN.BOLT
    ;;
*)
echo "Invalid input..."
exit 1
;;
esac