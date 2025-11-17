import numpy as np 

class ClassName(object):
	"""docstring for ClassName"""
	def __init__(self, arg):
		super(ClassName, self).__init__()
		self.arg = arg

class modulator():

		def __init__(self, bitrate, freq_if_mult, sample_rate, seed=1):
			super(modulator, self).__init__()

			delta_f = bitrate/4
			freq_if = delta_f * freq_if_mult

			self.freq_f1 = freq_if - delta_f
			self.freq_f2 = freq_if + delta_f

			self.sample_rate = sample_rate

			self.nco_f1 = nco(self.freq_f1, self.sample_rate)
			self.nco_f2 = nco(self.freq_f2, self.sample_rate)

			self.prbs = prbs(seed);
			self.encoder = encoder();

			self.samples_per_bit = sample_rate / bitrate
			self.sample_counter = 0

		def init(self):
			self.sample_counter = 0

		def get_sample(self):
			if sample_counter == 0:
				self.bit = self.prbs.git_bit()
			return self.bit


class prbs():

	def __init__(self, seed):
		super(prbs, self).__init__()
		self.seed = seed

	def get_bit(self):
		return 1


class encoder():
	"""Differential Encoder for MSK Modem"""
	def __init__(self):
		super(encoder, self).__init__()
		self.x_xor = 0
		self.b  = 1

	def init(self):
		self.x_xor = 0
		self.b  = 1

	def encode(self, bit):
		
		pos = (bit + 1) >> 1
		neg = (bit - 1) >> 1

		pos_xor = pos * self.x_xor

		neg_b = neg * self.b

		neg_xor = neg_b * self.x_xor


		self.x_xor = bit * self.x_xor
		self.b = -1 * self.b

		return pos, neg;


class nco():
	"""NCO"""
	def __init__(self, freq, sample_rate):
		super(nco, self).__init__()
		self.freq = freq
		self.step = 1/sample_rate

	def init(self):
		self.step = 0

	def get_sample(self):
		sample_cos = np.cos(2*np.pi*self.freq+self.step)
		sample_sin = np.sin(2*np.pi*self.freq+self.step)
		return cos, sin
