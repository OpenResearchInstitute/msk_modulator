import numpy as np 

from nco.model.nco   	import nco
from prbs.model.prbs	import prbs

class modulator():

		def __init__(self, bitrate, freq_if_mult, sample_rate, seed=1):
			super(modulator, self).__init__()

			self.bitrate = bitrate

			delta_f = bitrate/4
			freq_if = delta_f * freq_if_mult

			self.freq_f1 = freq_if - delta_f
			self.freq_f2 = freq_if + delta_f
			print("delta_f", delta_f)
			print("freq_if", freq_if)
			print("f1: ", self.freq_f1)
			print("f2: ", self.freq_f2)

			self.sample_rate = sample_rate

			self.nco_br = nco.nco(self.bitrate, self.sample_rate)
			self.nco_f1 = nco.nco(self.freq_f1, self.sample_rate)
			self.nco_f2 = nco.nco(self.freq_f2, self.sample_rate)

			self.encoder  = encoder();

			self.samples_per_bit = sample_rate / bitrate

			self.f1s = 0
			self.f2s = 0
			

		def init(self):
			self.sample_counter = 0
			self.nco_f1.init()
			self.nco_f2.init()

		def txbit(self, bit):
			self.pos_neg = self.encoder.encode(bit)
			#print("bit: ", bit, "pos: ", self.pos_neg[0], "neg: ", self.pos_neg[1])

		def get_sample(self):
			f1 = self.nco_f1.get_sin_cos()
			f2 = self.nco_f2.get_sin_cos()
			br = self.nco_br.get_sin_cos()
			#print("freq: %f %f" % (f1[0], f2[0]))

			rollover = br[2]

			self.f1s = f1[0] * self.pos_neg[0]
			self.f1c = f1[1] * self.pos_neg[0]

			self.f2s = f2[0] * self.pos_neg[1]
			self.f2c = f2[1] * self.pos_neg[1]

			b_raw = f1[1] * f2[1] + f1[0] * f2[0] # cos(f1) * sin(f2)
			self.encoder.b = -1 if b_raw >= 0 else 1  # Convert to ±1
			print(b_raw, self.encoder.b)

			#print("f1s: %f f1c: %f f2s: %f f2c: %f" % (f1s, f1c, f2s, f2c))

			txss = self.f1s + self.f2s
			txsc = self.f1c + self.f2c

			#print ("txss: %f txsc: %f" % (txss, txsc))

			return [txss, txsc, rollover]


class encoder():
	"""Differential Encoder for MSK Modem"""
	def __init__(self):
		super(encoder, self).__init__()
		self.x_xor = 1
		self.b  = -1

	def init(self):
		self.x_xor = 1
		self.b  = -1

	def encode(self, bit):

		twobit = -1 if bit==1 else 1

		pos_x = (twobit + 1) >> 1
		neg_y = (twobit - 1) >> 1
		
		neg_b   = neg_y * self.b
		pos_xor = pos_x * self.x_xor
		neg_xor = neg_b * self.x_xor


		print("bit: %2d; twobit: %2d; pos_x: %2d; neg_y: %2d; b: %2d; neg_b: %2d, pos_xor: %2d; neg_xor: %2d; x_xor: %2d" %
					(bit, twobit, pos_x, neg_y, self.b, neg_b, pos_xor, neg_xor, self.x_xor))

		self.x_xor = twobit * self.x_xor
		#self.b 	   =     -1 * self.b

		return [pos_xor, neg_xor];
