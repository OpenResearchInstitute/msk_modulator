#!/usr/bin/env python

from msk_modulator import msk_modulator

bitrate 	 = 54200
freq_if_mult = 32
sample_rate  = 61.44e6


mod = msk_modulator.modulator(bitrate, freq_if_mult, sample_rate)



