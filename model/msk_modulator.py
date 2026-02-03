#!/usr/bin/env python

import sys
import os
import pyqtgraph as pg
from   pyqtgraph.Qt import QtCore
import numpy as np

# Add the parent directory (where all submodules live) to Python path
submodule_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
project_root = os.path.dirname(submodule_root)
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from msk_modulator   import msk_modulator
from prbs.model.prbs import prbs

bitrate 	 = 54200
freq_if_mult = 32
sample_rate  = 5e6 #61.44e6

mod = msk_modulator.modulator(bitrate, freq_if_mult, sample_rate)
gen = prbs.prbs_generator()

app = pg.mkQApp()
win = pg.GraphicsLayoutWidget(show=True, title="Realtime Plot")

	# Create two plots
p1 = win.addPlot(title="I Channel")
p2 = win.addPlot(title="Q Channel", row=1, col=0)
p3 = win.addPlot(title="Q Channel", row=2, col=0)

curve1 = p1.plot(pen='r')
curve2 = p1.plot(pen='b')
curve3 = p2.plot(pen='g')
curve4 = p3.plot(pen='y')

sample_buffer = np.zeros(250)
bit_buffer = np.zeros(250)
f1_buffer = np.zeros(250)
f2_buffer = np.zeros(250)

ptr = 0

iq = [0, 0, 1]
bit = 0

def update():
	global sample_buffer, bit_buffer, ptr, iq, bit, f1_buffer, f2_buffer

	if iq[2]:
		bit = gen.bit()
		print("bit: ", bit)
		mod.txbit(bit)

	iq  = mod.get_sample()
	new_sample = iq[0]
	new_f1s = mod.f1s 
	new_f2s = mod.f2s

	sample_buffer[:-1] = sample_buffer[1:]
	sample_buffer[-1]  = new_sample
	    
	bit_buffer[:-1] = bit_buffer[1:]
	bit_buffer[-1]  = bit

	f1_buffer[:-1] = f1_buffer[1:]
	f1_buffer[-1]  = new_f1s

	f2_buffer[:-1] = f2_buffer[1:]
	f2_buffer[-1]  = new_f2s

	curve1.setData(sample_buffer)
	curve2.setData(bit_buffer)
	curve3.setData(f1_buffer)
	curve4.setData(f2_buffer)

timer = QtCore.QTimer()
timer.timeout.connect(update)
timer.start(50)  # 50ms update rate

app.exec_()
