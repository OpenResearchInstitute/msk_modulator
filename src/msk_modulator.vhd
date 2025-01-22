------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------
--  _______                             ________                                            ______
--  __  __ \________ _____ _______      ___  __ \_____ _____________ ______ ___________________  /_
--  _  / / /___  __ \_  _ \__  __ \     __  /_/ /_  _ \__  ___/_  _ \_  __ `/__  ___/_  ___/__  __ \
--  / /_/ / __  /_/ //  __/_  / / /     _  _, _/ /  __/_(__  ) /  __// /_/ / _  /    / /__  _  / / /
--  \____/  _  .___/ \___/ /_/ /_/      /_/ |_|  \___/ /____/  \___/ \__,_/  /_/     \___/  /_/ /_/
--          /_/
--                   ________                _____ _____ _____         _____
--                   ____  _/_______ __________  /____(_)__  /_____  ____  /______
--                    __  /  __  __ \__  ___/_  __/__  / _  __/_  / / /_  __/_  _ \
--                   __/ /   _  / / /_(__  ) / /_  _  /  / /_  / /_/ / / /_  /  __/
--                   /___/   /_/ /_/ /____/  \__/  /_/   \__/  \__,_/  \__/  \___/
--
------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------
-- Copyright
------------------------------------------------------------------------------------------------------
--
-- Copyright 2024 by M. Wishek <matthew@wishek.com>
--
------------------------------------------------------------------------------------------------------
-- License
------------------------------------------------------------------------------------------------------
--
-- This source describes Open Hardware and is licensed under the CERN-OHL-W v2.
--
-- You may redistribute and modify this source and make products using it under
-- the terms of the CERN-OHL-W v2 (https://ohwr.org/cern_ohl_w_v2.txt).
--
-- This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
-- OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A PARTICULAR PURPOSE.
-- Please see the CERN-OHL-W v2 for applicable conditions.
--
-- Source location: TBD
--
-- As per CERN-OHL-W v2 section 4.1, should You produce hardware based on this
-- source, You must maintain the Source Location visible on the external case of
-- the products you make using this source.
--
------------------------------------------------------------------------------------------------------
-- Block name and description
------------------------------------------------------------------------------------------------------
--
-- This block implements and MSK Modulator.
--
-- Documentation location: TBD
--
------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------


------------------------------------------------------------------------------------------------------
-- ╦  ┬┌┐ ┬─┐┌─┐┬─┐┬┌─┐┌─┐
-- ║  │├┴┐├┬┘├─┤├┬┘│├┤ └─┐
-- ╩═╝┴└─┘┴└─┴ ┴┴└─┴└─┘└─┘
------------------------------------------------------------------------------------------------------
-- Libraries

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;


------------------------------------------------------------------------------------------------------
-- ╔═╗┌┐┌┌┬┐┬┌┬┐┬ ┬
-- ║╣ │││ │ │ │ └┬┘
-- ╚═╝┘└┘ ┴ ┴ ┴  ┴ 
------------------------------------------------------------------------------------------------------
-- Entity

ENTITY msk_modulator IS 
	GENERIC (
		NCO_W 			: NATURAL := 32;
		PHASE_W 		: NATURAL := 10;
		SINUSOID_W 		: NATURAL := 12;
		SAMPLE_W 		: NATURAL := 12
	);
	PORT (
		clk 				: IN  std_logic;
		init 				: IN  std_logic;

		freq_word_tclk 		: IN  std_logic_vector(NCO_W -1 DOWNTO 0);
		freq_word_f1 		: IN  std_logic_vector(NCO_W -1 DOWNTO 0);
		freq_word_f2	 	: IN  std_logic_vector(NCO_W -1 DOWNTO 0);

		tx_data 			: IN  std_logic;
		tx_req 				: OUT std_logic;

		ptt 			    : IN  std_logic;

		tx_enable 			: IN  std_logic;
		tx_valid 			: IN  std_logic;
		tx_samples_I		: OUT std_logic_vector(SAMPLE_W -1 DOWNTO 0);
		tx_samples_Q		: OUT std_logic_vector(SAMPLE_W -1 DOWNTO 0)
	);
END ENTITY msk_modulator;


------------------------------------------------------------------------------------------------------
-- ╔═╗┬─┐┌─┐┬ ┬┬┌┬┐┌─┐┌─┐┌┬┐┬ ┬┬─┐┌─┐
-- ╠═╣├┬┘│  ├─┤│ │ ├┤ │   │ │ │├┬┘├┤ 
-- ╩ ╩┴└─└─┘┴ ┴┴ ┴ └─┘└─┘ ┴ └─┘┴└─└─┘
------------------------------------------------------------------------------------------------------
-- Architecture

ARCHITECTURE rtl OF msk_modulator IS 

	TYPE signed_array IS ARRAY(0 TO 2) OF signed(SINUSOID_W -1 DOWNTO 0);

	SIGNAL tx_init 				: std_logic;

	SIGNAL tclk 				: std_logic;

	SIGNAL carrier_phase_f1		: std_logic_vector(NCO_W -1 DOWNTO 0);
	SIGNAL carrier_phase_f2		: std_logic_vector(NCO_W -1 DOWNTO 0);
	SIGNAL carrier_sin_f1		: std_logic_vector(SINUSOID_W -1 DOWNTO 0);
	SIGNAL carrier_sin_f2		: std_logic_vector(SINUSOID_W -1 DOWNTO 0);
	SIGNAL carrier_sin_f1_dly 	: signed_array;
	SIGNAL carrier_sin_f2_dly 	: signed_array;
	SIGNAL carrier_cos_f1		: std_logic_vector(SINUSOID_W -1 DOWNTO 0);
	SIGNAL carrier_cos_f2		: std_logic_vector(SINUSOID_W -1 DOWNTO 0);
	SIGNAL carrier_cos_f1_dly 	: signed_array;
	SIGNAL carrier_cos_f2_dly 	: signed_array;

	SIGNAL tclk_dly 			: std_logic_vector(0 TO 3);

	SIGNAL tx_data_reg			: std_logic;

	SIGNAL d_val 		 		: signed(2 DOWNTO 0);
	SIGNAL d_pos, d_neg 		: signed(1 DOWNTO 0);
	SIGNAL d_enc, d_enc_t		: signed(1 DOWNTO 0);
	SIGNAL d_n_b 				: signed(1 DOWNTO 0);
	SIGNAL d_pos_enc 			: signed(1 DOWNTO 0);
	SIGNAL d_neg_enc 			: signed(1 DOWNTO 0);
	SIGNAL d_s1, d_s2 			: signed(1 DOWNTO 0);

	SIGNAL s1s, s2s				: signed(SINUSOID_W -1 DOWNTO 0);
	SIGNAL s1c, s2c				: signed(SINUSOID_W -1 DOWNTO 0);

	SIGNAL b_n 					: std_logic;

BEGIN


	tx_init 	<= init OR NOT tx_enable;


------------------------------------------------------------------------------------------------------
--  __       ___                __       ___ 
-- |  \  /\   |   /\    | |\ | |__) /  \  |  
-- |__/ /--\  |  /--\   | | \| |    \__/  |  
--                                           
------------------------------------------------------------------------------------------------------
-- Data Input

	tx_req 		<= tclk WHEN ptt = '1' ELSE '0';

	get_data_proc : PROCESS (clk)
	BEGIN
		IF clk'EVENT AND clk = '1' THEN

			IF tx_valid = '1' THEN

				tclk_dly <= tclk & tclk_dly(0 TO 2);
	
				IF tclk_dly(0) = '1' AND ptt = '1' THEN
					tx_data_reg	<= tx_data;
				END IF;

			END IF;
	
			IF tx_init = '1' THEN 
				tclk_dly 	<= (OTHERS => '0');
				tx_data_reg	<= '0';
			END IF;

		END IF;
	END PROCESS get_data_proc;


------------------------------------------------------------------------------------------------------
--  __       ___         __       __  __   __   __  __  
-- |  \  /\   |   /\    |_  |\ | /   /  \ |  \ |_  |__) 
-- |__/ /--\  |  /--\   |__ | \| \__ \__/ |__/ |__ | \  
--                                                      
------------------------------------------------------------------------------------------------------
-- Data Encoder

	d_val <= "001" WHEN tx_data_reg = '0' ELSE "111";  -- 0 -> 1 and 1 -> -1

	d_pos <= resize(shift_right(d_val + 1, 1), 2);
	d_neg <= resize(shift_right(d_val - 1, 1), 2);

	-- The following implements a multiplier as a mux
	d_enc <= "01" WHEN tx_data_reg = '0' AND d_enc_t = "01" ELSE
	         "01" WHEN tx_data_reg = '1' AND d_enc_t = "11" ELSE
	         "11";

	-- The following implements a multiplier as a mux
	-- d_n_b <= d_neg * b_n (when both d_neg is in {-1,0,+1} and b_n is in {-1,+1}
	d_n_b <= "00" WHEN d_neg = "00" ELSE
			 "01" WHEN d_neg = "01" AND b_n = '0' ELSE
			 "01" WHEN d_neg = "11" AND b_n = '1' ELSE
			 "11";

	d_pos_enc <= d_pos WHEN d_enc_t = "01" ELSE NOT(d_pos) + 1;
	d_neg_enc <= d_n_b WHEN d_enc_t = "01" ELSE NOT(d_n_b) + 1;

	enc_proc : PROCESS (clk)
	BEGIN
		IF clk'EVENT AND clk = '1' THEN

			IF tx_valid = '1' THEN

				IF tclk_dly(0) = '1' THEN 
	
					b_n 	<= NOT b_n;					-- b[n] = (-1)^n
					d_enc_t	<= d_enc;
	
				END IF;
	
				IF tclk_dly(1) = '1' THEN
	
					d_s1 	<= d_pos_enc;
					d_s2 	<= d_neg_enc;
	
				END IF;

			END IF;

			IF tx_init = '1' THEN
				b_n 	<= '1';
				d_enc_t	<= "01";
				d_s1 	<= "00";
				d_s2	<= "00";
			END IF;

		END IF;
	END PROCESS enc_proc;


------------------------------------------------------------------------------------------------------
--  __       __   __     __  __          __   __                ___    __       
-- /    /\  |__) |__) | |_  |__)   |\/| /  \ |  \ /  \ |    /\   |  | /  \ |\ | 
-- \__ /--\ | \  | \  | |__ | \    |  | \__/ |__/ \__/ |__ /--\  |  | \__/ | \| 
--                                                                              
------------------------------------------------------------------------------------------------------
-- Carrier Modulation

	carrier_mod_proc : PROCESS (clk)
		VARIABLE v_sin_f1_d : signed(SINUSOID_W -1 DOWNTO 0);
		VARIABLE v_sin_f1_n : signed(SINUSOID_W -1 DOWNTO 0);
		VARIABLE v_sin_f2_d : signed(SINUSOID_W -1 DOWNTO 0);
		VARIABLE v_sin_f2_n : signed(SINUSOID_W -1 DOWNTO 0);
		VARIABLE v_cos_f1_d : signed(SINUSOID_W -1 DOWNTO 0);
		VARIABLE v_cos_f1_n : signed(SINUSOID_W -1 DOWNTO 0);
		VARIABLE v_cos_f2_d : signed(SINUSOID_W -1 DOWNTO 0);
		VARIABLE v_cos_f2_n : signed(SINUSOID_W -1 DOWNTO 0);
	BEGIN
		IF clk'EVENT AND clk = '1' THEN

			IF tx_valid = '1' THEN

				v_sin_f1_d 	:= carrier_sin_f1_dly(2);
				v_sin_f1_n 	:= NOT(carrier_sin_f1_dly(2)) + 1;
				v_sin_f2_d 	:= carrier_sin_f2_dly(2);
				v_sin_f2_n 	:= NOT(carrier_sin_f2_dly(2)) + 1;
				v_cos_f1_d 	:= carrier_cos_f1_dly(2);
				v_cos_f1_n 	:= NOT(carrier_cos_f1_dly(2)) + 1;
				v_cos_f2_d 	:= carrier_cos_f2_dly(2);
				v_cos_f2_n 	:= NOT(carrier_cos_f2_dly(2)) + 1;

				carrier_sin_f1_dly 	<= signed(carrier_sin_f1) & carrier_sin_f1_dly(0 TO 1);
				carrier_sin_f2_dly 	<= signed(carrier_sin_f2) & carrier_sin_f2_dly(0 TO 1);
				carrier_cos_f1_dly 	<= signed(carrier_cos_f1) & carrier_cos_f1_dly(0 TO 1);
				carrier_cos_f2_dly 	<= signed(carrier_cos_f2) & carrier_cos_f2_dly(0 TO 1);

				CASE d_s1 IS 
					WHEN "11" 	=> s1c <= resize(v_cos_f1_n, SINUSOID_W); 	-- Multiply by -1
								   s1s <= resize(v_sin_f1_n, SINUSOID_W); 
					WHEN "01" 	=> s1c <= resize(v_cos_f1_d, SINUSOID_W);	-- Multiply by +1
								   s1s <= resize(v_sin_f1_d, SINUSOID_W);
					WHEN OTHERS => s1c <= (OTHERS => '0'); 					-- Multiply by  0
								   s1s <= (OTHERS => '0');
				END CASE;

				CASE d_s2 IS 
					WHEN "11" 	=> s2c <= resize(v_cos_f2_n, SINUSOID_W); 	-- Multiply by -1
								   s2s <= resize(v_sin_f2_n, SINUSOID_W); 
					WHEN "01" 	=> s2c <= resize(v_cos_f2_d, SINUSOID_W);	-- Multiply by +1
								   s2s <= resize(v_sin_f2_d, SINUSOID_W);
					WHEN OTHERS => s2c <= (OTHERS => '0'); 					-- Multiply by  0
								   s2s <= (OTHERS => '0');
				END CASE;

				IF ptt = '1' THEN
					tx_samples_I <= std_logic_vector(resize(s1s + s2s, SAMPLE_W));
					tx_samples_Q <= std_logic_vector(resize(s1c + s2c, SAMPLE_W));
				ELSE
					tx_samples_I <= (OTHERS => '0');
					tx_samples_Q <= (OTHERS => '0');
				END IF;

			END IF;

			IF tx_init = '1' THEN
				s1s <= (OTHERS => '0');
				s2s <= (OTHERS => '0');
				s1c <= (OTHERS => '0');
				s2c <= (OTHERS => '0');
				tx_samples_I <= (OTHERS => '0');
				tx_samples_Q <= (OTHERS => '0');
			END IF;
		END IF;
	END PROCESS carrier_mod_proc;


------------------------------------------------------------------------------------------------------
--  __           __   __        ___         __         __  __  
-- (_  \_/ |\/| |__) /  \ |      |  | |\/| |_    |\ | /   /  \ 
-- __)  |  |  | |__) \__/ |__    |  | |  | |__   | \| \__ \__/ 
--                                                             
------------------------------------------------------------------------------------------------------
-- Symbol Time NCO

	U_tclk_nco : ENTITY work.nco(rtl)
	GENERIC MAP(
		NCO_W 			=> NCO_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> tx_init,

		enable 			=> tx_valid,
	
		discard_nco 	=> std_logic_vector(to_unsigned(0, 8)),
		freq_word 		=> freq_word_tclk,

		freq_adj_zero   => '0',
		freq_adj_valid  => '0',
		freq_adjust 	=> std_logic_vector(to_signed(0, NCO_W)),
	
		phase    		=> OPEN,
		rollover_pi2 	=> OPEN,
		rollover_pi 	=> OPEN,
		rollover_3pi2 	=> OPEN,
		rollover_2pi 	=> tclk,
		tclk_even		=> OPEN,
		tclk_odd		=> OPEN
	);


------------------------------------------------------------------------------------------------------
--       __  __     __     
-- |\ | /   /  \   |_   /| 
-- | \| \__ \__/   |     | 
--                         
------------------------------------------------------------------------------------------------------
-- NCO F1

	U_f1_nco : ENTITY work.nco(rtl)
	GENERIC MAP(
		NCO_W 			=> NCO_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> tx_init,

		enable 			=> tx_valid,
	
		freq_word 		=> freq_word_f1,

		discard_nco 	=> std_logic_vector(to_unsigned(0, 8)),
		freq_adj_zero   => '0',
		freq_adj_valid  => '0',
		freq_adjust 	=> std_logic_vector(to_signed(0, NCO_W)),
	
		phase    		=> carrier_phase_f1,
		rollover_pi2 	=> OPEN,
		rollover_pi 	=> OPEN,
		rollover_3pi2 	=> OPEN,
		rollover_2pi 	=> OPEN,
		tclk_even		=> OPEN,
		tclk_odd		=> OPEN
	);

	U_f1_sin_cos_lut : ENTITY work.sin_cos_lut(lut_based)
	GENERIC MAP(
		PHASE_W 		=> PHASE_W,
		PHASES 			=> 2**PHASE_W,
		SINUSOID_W 		=> SINUSOID_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> tx_init,
	
		phase 			=> carrier_phase_f1(NCO_W -1 DOWNTO NCO_W - PHASE_W),

		sin_out			=> carrier_sin_f1,
		cos_out			=> carrier_cos_f1
	);


------------------------------------------------------------------------------------------------------
--       __  __     __  __  
-- |\ | /   /  \   |_    _) 
-- | \| \__ \__/   |    /__ 
--                          
------------------------------------------------------------------------------------------------------
-- NCO F2

	U_f2_nco : ENTITY work.nco(rtl)
	GENERIC MAP(
		NCO_W 			=> NCO_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> tx_init,
	
		enable 			=> tx_valid,

		freq_word 		=> freq_word_f2,

		discard_nco 	=> std_logic_vector(to_unsigned(0, 8)),
		freq_adj_zero   => '0',
		freq_adj_valid  => '0',
		freq_adjust 	=> std_logic_vector(to_signed(0, NCO_W)),
	
		phase    		=> carrier_phase_f2,
		rollover_pi2 	=> OPEN,
		rollover_pi 	=> OPEN,
		rollover_3pi2 	=> OPEN,
		rollover_2pi 	=> OPEN,
		tclk_even		=> OPEN,
		tclk_odd		=> OPEN
	);

	U_f2_sin_cos_lut : ENTITY work.sin_cos_lut(lut_based)
	GENERIC MAP(
		PHASE_W 		=> PHASE_W,
		PHASES 			=> 2**PHASE_W,
		SINUSOID_W 		=> SINUSOID_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> tx_init,
	
		phase 			=> carrier_phase_f2(NCO_W -1 DOWNTO NCO_W - PHASE_W),

		sin_out			=> carrier_sin_f2,
		cos_out			=> carrier_cos_f2
	);


END ARCHITECTURE rtl;