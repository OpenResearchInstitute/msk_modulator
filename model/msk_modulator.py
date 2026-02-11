"""
Python model of msk_modulator.vhd — MSK Modulator.

RTL architecture:
  - 3 NCOs: tclk (symbol timing), F1, F2
  - tclk NCO rollover_2pi generates tclk (symbol boundary)
  - Data input: on tclk, latch tx_data (with optional sync pattern insertion)
  - Differential encoder: d_val=+1/-1, XOR with previous, separate F1/F2 coefficients
  - Carrier modulation: multiply NCO sin/cos by d_s1/d_s2 (+1/-1/0)
  - Output: tx_samples_I = s1s+s2s, tx_samples_Q = s1c+s2c (gated by ptt)

Sync pattern:
  - On PTT rising edge with tx_sync_ena, loads sync_counter from tx_sync_cnt
  - While counter > 0, outputs sync_nibble[counter(1:0)] = "0101" pattern
  - tx_sync_force overrides data with sync pattern indefinitely
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from model_utils import signed, unsigned
from nco.model.nco import Nco


class MskModulator:
    def __init__(self, nco_w=32, phase_w=10, sinusoid_w=12, sample_w=12,
                 sync_cnt_w=24, fixed_point=False):
        self.NCO_W = nco_w
        self.PHASE_W = phase_w
        self.SINUSOID_W = sinusoid_w
        self.SAMPLE_W = sample_w
        self.SYNC_CNT_W = sync_cnt_w
        self.fixed_point = fixed_point

        self.SYNC_NIBBLE = [0, 1, 0, 1]  # "0101" indexed by counter(1:0)

        # Create NCO instances
        self.nco_tclk = Nco(nco_w=nco_w, phase_w=phase_w, sinusoid_w=sinusoid_w,
                            fixed_point=fixed_point)
        self.nco_f1 = Nco(nco_w=nco_w, phase_w=phase_w, sinusoid_w=sinusoid_w,
                          fixed_point=fixed_point)
        self.nco_f2 = Nco(nco_w=nco_w, phase_w=phase_w, sinusoid_w=sinusoid_w,
                          fixed_point=fixed_point)

        self.reset()

    def reset(self):
        self.nco_tclk.reset()
        self.nco_f1.reset()
        self.nco_f2.reset()

        SW = self.SINUSOID_W

        self.tclk = 0
        self.tclk_dly = [0, 0, 0, 0]
        self.tx_data_reg = 0
        self.sync_counter = 0
        self.ptt_d = 0

        # Encoder state
        self.d_val_xor_T = 0  # 3-bit signed, init "000"
        self.b_n = 1  # init '1'
        self.d_s1 = 0  # 2-bit signed
        self.d_s2 = 0  # 2-bit signed

        # Carrier delay lines (3 deep)
        if self.fixed_point:
            self.sin_f1_dly = [0, 0, 0]
            self.sin_f2_dly = [0, 0, 0]
            self.cos_f1_dly = [0, 0, 0]
            self.cos_f2_dly = [0, 0, 0]
        else:
            self.sin_f1_dly = [0.0, 0.0, 0.0]
            self.sin_f2_dly = [0.0, 0.0, 0.0]
            self.cos_f1_dly = [0.0, 0.0, 0.0]
            self.cos_f2_dly = [0.0, 0.0, 0.0]

        self.s1s = 0
        self.s2s = 0
        self.s1c = 0
        self.s2c = 0
        self._tx_samples_I = 0
        self._tx_samples_Q = 0
        self._tx_req = 0

    def step(self, tx_data, tx_enable, tx_valid, ptt,
             freq_word_tclk, freq_word_f1, freq_word_f2,
             tx_sync_ena=0, tx_sync_cnt=0, tx_sync_force=0):
        """One clock cycle. Returns dict of outputs."""

        tx_init = not tx_enable

        # Step NCOs
        tclk_out = self.nco_tclk.step(enable=tx_valid, freq_word=freq_word_tclk)
        f1_out = self.nco_f1.step(enable=tx_valid, freq_word=freq_word_f1)
        f2_out = self.nco_f2.step(enable=tx_valid, freq_word=freq_word_f2)

        self.tclk = tclk_out['rollover_2pi']
        self._tx_req = self.tclk if ptt else 0

        if self.fixed_point:
            return self._step_fixed(tx_data, tx_init, tx_valid, ptt,
                                    f1_out, f2_out, tx_sync_ena, tx_sync_cnt, tx_sync_force)
        else:
            return self._step_float(tx_data, tx_init, tx_valid, ptt,
                                    f1_out, f2_out, tx_sync_ena, tx_sync_cnt, tx_sync_force)

    def _step_float(self, tx_data, tx_init, tx_valid, ptt,
                    f1_out, f2_out, tx_sync_ena, tx_sync_cnt, tx_sync_force):
        """Floating-point mode - simplified MSK modulation."""
        SW = self.SINUSOID_W
        SampleW = self.SAMPLE_W

        if tx_valid:
            # PPT pulse detection
            ptt_pulse = ptt and not self.ptt_d
            self.ptt_d = ptt

            # tclk delay shift
            self.tclk_dly = [self.tclk] + self.tclk_dly[:3]

            if ptt_pulse and tx_sync_ena:
                self.sync_counter = tx_sync_cnt

            # Data latch on tclk_dly[0]
            if self.tclk_dly[0] and ptt:
                if self.sync_counter > 0 or tx_sync_force:
                    self.tx_data_reg = self.SYNC_NIBBLE[self.sync_counter & 0x3]
                    if self.sync_counter > 0:
                        self.sync_counter -= 1
                else:
                    self.tx_data_reg = tx_data

            # Differential encoding
            d_val = 1.0 if self.tx_data_reg == 0 else -1.0

            if self.tclk_dly[0]:
                self.b_n = not self.b_n

            # Simple MSK: multiply carriers by data sign
            sin_f1 = f1_out['sin']
            cos_f1 = f1_out['cos']
            sin_f2 = f2_out['sin']
            cos_f2 = f2_out['cos']

            if ptt:
                self._tx_samples_I = sin_f1 * d_val + sin_f2 * d_val
                self._tx_samples_Q = cos_f1 * d_val + cos_f2 * d_val
            else:
                self._tx_samples_I = 0.0
                self._tx_samples_Q = 0.0

        if tx_init:
            self.tclk_dly = [0, 0, 0, 0]
            self.tx_data_reg = 0
            self.sync_counter = 0
            self.ptt_d = 0
            self.b_n = 1
            self.d_s1 = 0
            self.d_s2 = 0
            self._tx_samples_I = 0.0
            self._tx_samples_Q = 0.0

        return {
            'tx_samples_I': self._tx_samples_I,
            'tx_samples_Q': self._tx_samples_Q,
            'tx_req': self._tx_req,
        }

    def _step_fixed(self, tx_data, tx_init, tx_valid, ptt,
                    f1_out, f2_out, tx_sync_ena, tx_sync_cnt, tx_sync_force):
        """Fixed-point mode matching RTL pipeline."""
        SW = self.SINUSOID_W
        SampleW = self.SAMPLE_W

        if tx_valid:
            # PPT pulse detection
            ptt_pulse = 1 if (ptt and not self.ptt_d) else 0
            self.ptt_d = ptt

            # tclk delay shift register
            self.tclk_dly = [self.tclk] + self.tclk_dly[:3]

            if ptt_pulse and tx_sync_ena:
                self.sync_counter = tx_sync_cnt & ((1 << self.SYNC_CNT_W) - 1)

            sync_counter_next = max(0, self.sync_counter - 1) if self.sync_counter > 0 else 0

            # Data input (on tclk_dly[0])
            if self.tclk_dly[0] and ptt:
                if self.sync_counter > 0 or tx_sync_force:
                    self.tx_data_reg = self.SYNC_NIBBLE[self.sync_counter & 0x3]
                    self.sync_counter = sync_counter_next
                else:
                    self.tx_data_reg = tx_data & 1

            # Data encoder
            # d_val: 0->+1 ("001"), 1->-1 ("111") as 3-bit signed
            d_val = 1 if self.tx_data_reg == 0 else -1

            # d_val_xor: XOR d_val with d_val_xor_T
            if d_val == 1 and self.d_val_xor_T >= 0:
                d_val_xor = 1
            elif d_val == 1 and self.d_val_xor_T < 0:
                d_val_xor = -1
            elif d_val == -1 and self.d_val_xor_T >= 0:
                d_val_xor = -1
            else:
                d_val_xor = 1

            # d_pos = (d_val+1)/2, d_neg = (d_val-1)/2
            d_pos = (d_val + 1) >> 1  # 0 or 1
            d_neg = (d_val - 1) >> 1  # -1 or 0
            d_pos_enc = d_pos

            b_neg = -d_neg if self.b_n == 0 else d_neg
            d_neg_enc = b_neg

            # d_pos_xor and d_neg_xor encoding
            if d_pos_enc == 1 and self.d_val_xor_T >= 0:
                d_pos_xor = 1  # "01"
            elif d_pos_enc == 1 and self.d_val_xor_T < 0:
                d_pos_xor = -1  # "11"
            else:
                d_pos_xor = 0  # "00"

            if d_neg_enc == -1 and self.d_val_xor_T >= 0:
                d_neg_xor = -1  # "11"
            elif d_neg_enc == -1 and self.d_val_xor_T < 0:
                d_neg_xor = 1  # "01"
            elif d_neg_enc == 1 and self.d_val_xor_T >= 0:
                d_neg_xor = 1  # "01"
            elif d_neg_enc == 1 and self.d_val_xor_T < 0:
                d_neg_xor = -1  # "11"
            else:
                d_neg_xor = 0  # "00"

            # Encoder register updates
            if self.tclk_dly[0]:
                self.d_val_xor_T = d_val_xor
                self.b_n = 1 - self.b_n  # toggle

            if self.tclk_dly[1]:
                self.d_s1 = d_pos_xor
                self.d_s2 = d_neg_xor

            # Carrier modulation
            sin_f1 = f1_out['sin']
            cos_f1 = f1_out['cos']
            sin_f2 = f2_out['sin']
            cos_f2 = f2_out['cos']

            # Delay lines (3 deep, shift in at front)
            v_sin_f1_d = self.sin_f1_dly[2]
            v_sin_f2_d = self.sin_f2_dly[2]
            v_cos_f1_d = self.cos_f1_dly[2]
            v_cos_f2_d = self.cos_f2_dly[2]

            self.sin_f1_dly = [sin_f1] + self.sin_f1_dly[:2]
            self.sin_f2_dly = [sin_f2] + self.sin_f2_dly[:2]
            self.cos_f1_dly = [cos_f1] + self.cos_f1_dly[:2]
            self.cos_f2_dly = [cos_f2] + self.cos_f2_dly[:2]

            # Apply d_s1/d_s2 multiplication to delayed carriers
            if self.d_s1 == -1:
                self.s1c = signed(-v_cos_f1_d, SW)
                self.s1s = signed(-v_sin_f1_d, SW)
            elif self.d_s1 == 1:
                self.s1c = signed(v_cos_f1_d, SW)
                self.s1s = signed(v_sin_f1_d, SW)
            else:
                self.s1c = 0
                self.s1s = 0

            if self.d_s2 == -1:
                self.s2c = signed(-v_cos_f2_d, SW)
                self.s2s = signed(-v_sin_f2_d, SW)
            elif self.d_s2 == 1:
                self.s2c = signed(v_cos_f2_d, SW)
                self.s2s = signed(v_sin_f2_d, SW)
            else:
                self.s2c = 0
                self.s2s = 0

            if ptt:
                self._tx_samples_I = signed(self.s1s + self.s2s, SampleW)
                self._tx_samples_Q = signed(self.s1c + self.s2c, SampleW)
            else:
                self._tx_samples_I = 0
                self._tx_samples_Q = 0

        if tx_init:
            self.tclk_dly = [0, 0, 0, 0]
            self.tx_data_reg = 0
            self.sync_counter = 0
            self.ptt_d = 0
            self.d_val_xor_T = 0
            self.b_n = 1
            self.d_s1 = 0
            self.d_s2 = 0
            self.s1s = 0
            self.s2s = 0
            self.s1c = 0
            self.s2c = 0
            self._tx_samples_I = 0
            self._tx_samples_Q = 0

        return {
            'tx_samples_I': self._tx_samples_I,
            'tx_samples_Q': self._tx_samples_Q,
            'tx_req': self._tx_req,
        }


if __name__ == "__main__":
    import numpy as np

    # Fixed-point test
    mod = MskModulator(nco_w=32, phase_w=10, sinusoid_w=12, sample_w=12,
                       fixed_point=True)

    # Freq words for 4800 baud at 61.44 MHz
    fs = 61440000
    baud = 4800
    f1 = 1200  # mark
    f2 = 1800  # space
    fw_tclk = int(baud * (2**32) / fs)
    fw_f1 = int(f1 * (2**32) / fs)
    fw_f2 = int(f2 * (2**32) / fs)

    print(f"MSK Modulator test (baud={baud}, f1={f1}, f2={f2})")
    print(f"  fw_tclk=0x{fw_tclk:08x}, fw_f1=0x{fw_f1:08x}, fw_f2=0x{fw_f2:08x}")

    data_bits = [1, 0, 1, 1, 0, 0, 1, 0]
    bit_idx = 0
    req_count = 0

    for i in range(500):
        tx_data = data_bits[bit_idx % len(data_bits)]
        out = mod.step(
            tx_data=tx_data, tx_enable=1, tx_valid=1, ptt=1,
            freq_word_tclk=fw_tclk, freq_word_f1=fw_f1, freq_word_f2=fw_f2
        )
        if out['tx_req']:
            bit_idx += 1
            req_count += 1
        if i < 20 or out['tx_req']:
            print(f"  [{i:3d}] I={out['tx_samples_I']:5d}  Q={out['tx_samples_Q']:5d}  "
                  f"req={out['tx_req']}  bit={tx_data}")
    print(f"  Total tx_req pulses: {req_count}")
