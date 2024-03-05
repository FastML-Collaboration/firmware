onbreak {quit -f}
onerror {quit -f}

vsim -t 1ps -lib xil_defaultlib fifo_hitdata_19x128_opt

do {wave.do}

view wave
view structure
view signals

do {fifo_hitdata_19x128.udo}

run -all

quit -force
