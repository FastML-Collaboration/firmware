onbreak {quit -f}
onerror {quit -f}

vsim -t 1ps -lib xil_defaultlib fifo_chipdata_72x64_opt

do {wave.do}

view wave
view structure
view signals

do {fifo_chipdata_72x64.udo}

run -all

quit -force
