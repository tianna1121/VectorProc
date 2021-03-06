#!/bin/bash

# 
# Copyright 2011-2012 Jeff Bush
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 

BASEDIR=../..

mkdir -p WORK
$BASEDIR/tools/assembler/assemble -o WORK/mandelbrot.hex mandelbrot.asm

vvp $BASEDIR/rtl/sim.vvp +statetrace=statetrace.txt +bin=WORK/mandelbrot.hex +simcycles=250000 +memdumpbase=400 +memdumplen=4000 +memdumpfile=WORK/fb.bin +regtrace=1
#$BASEDIR/tools/simulator/iss -d WORK/fb.bin,400,4000 WORK/mandelbrot.hex 
$BASEDIR/tools/mkbmp/mkbmp WORK/fb.bin vsim.bmp 64 64
