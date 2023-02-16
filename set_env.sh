#!/bin/bash
command=$1
export SOURCE_CODE_DIR='/home/nn/binutils-gdb/binutils'
export MY_AFL_TOOL_PATH='/home/nn/AFL-Modify'
export BASE_WORK_DIR='/home/nn/work/testing'
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
sleep 3
export FUZZING_BIN='objdump'
export FUZZING_ARGS='-d'

export OUTPUT_BINARY_PATH=$BASE_WORK_DIR/bin
export LLVM_PROFILE_DIR=$BASE_WORK_DIR/prof
export MY_AFL_SEEDS_IN=$BASE_WORK_DIR/afl_in_seeds
export MY_AFL_OUTPUT_PATH=$BASE_WORK_DIR/afl_out
export PERF_RECORD_DIR=$BASE_WORK_DIR/perf_data
export BOLT_FORMAT_DATA_DIR=$BASE_WORK_DIR/bolt_format_prof

export CC=$MY_AFL_TOOL_PATH/afl-clang-lto 
export CXX=$MY_AFL_TOOL_PATH/afl-clang-lto++  
export CFLAGS='-fprofile-instr-generate -fcoverage-mapping' 
export CXXFLAGS='-fprofile-instr-generate -fcoverage-mapping' 
export LDFLAGS='-Wl,--emit-relocs'

compile(){
    cd $SOURCE_CODE_DIR
    ./configure --disable-shared 
    make -j12
    cp ./$1 $OUTPUT_BINARY_PATH/$1.ORIGINAL
}

fuzz(){
    export LLVM_PROFILE_FILE=$LLVM_PROFILE_DIR/$ROUND.profraw
    $MY_AFL_TOOL_PATH/afl-fuzz -m none -i $MY_AFL_SEEDS_IN -o $MY_AFL_OUTPUT_PATH.$ROUND -s 123 -D -M master -- $OUTPUT_BINARY_PATH/$1.$ROUND $2 @@
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
            # echo "perf record -e cycles:u -j any,u -o $outputfiledir/$cur_timestamp.data -- $OUTPUT_BINARY_PATH/$1.$ROUND $2 $i"
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
    find . -name "*.fdata" -print0 | xargs -0 merge-fdata -o $BASE_WORK_DIR/combined.data
    # merge-fdata $BOLT_FORMAT_DATA_DIR/* > $BASE_WORK_DIR/combined.data

    # change the binary
    llvm-bolt $OUTPUT_BINARY_PATH/$1.$ROUND -o $OUTPUT_BINARY_PATH/$2 -data=$BASE_WORK_DIR/combined.data  -reorder-blocks=ext-tsp -reorder-functions=hfsort -split-functions -split-all-cold -split-eh -dyno-stats
}

case $command in
  (compile)
  compile $FUZZING_BIN
     ;;

  (fuzz)
  fuzz $FUZZING_BIN $FUZZING_ARGS
     ;;

  (perf_record)
  perf_record $FUZZING_BIN $FUZZING_ARGS
     ;;

  (perf2bolt)
  perf_to_bolt $FUZZING_BIN
    ;;

  (merge)
  merge $FUZZING_BIN $FUZZING_BIN.BOLT
    ;;
    
  (*)
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
    if [ ! -d $MY_AFL_OUTPUT_PATH ]; then 
        mkdir $MY_AFL_OUTPUT_PATH
    fi
    if [ ! -d $PERF_RECORD_DIR ]; then 
        mkdir $PERF_RECORD_DIR
    fi
    if [ ! -d $BOLT_FORMAT_DATA_DIR ]; then 
        mkdir $BOLT_FORMAT_DATA_DIR
    fi
    ;;
esac