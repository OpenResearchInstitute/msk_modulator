

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;


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

		tclk_out			: OUT std_logic;

		freq_word_tclk 		: IN  std_logic_vector(NCO_W -1 DOWNTO 0);
		freq_word_f1 		: IN  std_logic_vector(NCO_W -1 DOWNTO 0);
		freq_word_f2	 	: IN  std_logic_vector(NCO_W -1 DOWNTO 0);

		tx_data 			: IN  std_logic;
		tx_req 				: OUT std_logic;

		tx_samples	 		: OUT std_logic_vector(SAMPLE_W -1 DOWNTO 0)
	);
END ENTITY msk_modulator;

ARCHITECTURE rtl OF msk_modulator IS 

	SIGNAL tclk_even		: std_logic;
	SIGNAL tclk_odd 		: std_logic;

	SIGNAL tclk 			: std_logic;

	SIGNAL carrier_phase_f1	: std_logic_vector(NCO_W -1 DOWNTO 0);
	SIGNAL carrier_phase_f2	: std_logic_vector(NCO_W -1 DOWNTO 0);
	SIGNAL carrier_cos_f1	: std_logic_vector(SINUSOID_W -1 DOWNTO 0);
	SIGNAL carrier_cos_f2	: std_logic_vector(SINUSOID_W -1 DOWNTO 0);

	SIGNAL tclk_dly 		: std_logic_vector(0 TO 3);

	SIGNAL tx_data_reg		: std_logic;

	SIGNAL d_val, d_dly 	: signed(2 DOWNTO 0);
	SIGNAL d_pos, d_neg 	: signed(1 DOWNTO 0);
	SIGNAL b_val 			: signed(1 DOWNTO 0);
	SIGNAL d_n_b 			: signed(1 DOWNTO 0);
	SIGNAL d_s1, d_s2 		: signed(1 DOWNTO 0);

	SIGNAL s1, s2 			: signed(SINUSOID_W -1 DOWNTO 0);

	SIGNAL b_n 				: std_logic;

BEGIN

	tclk 	 	<= tclk_even OR tclk_odd;
	tx_req 		<= tclk;
	tclk_out 	<= tclk;

	get_data_proc : PROCESS (clk)
	BEGIN
		IF clk'EVENT AND clk = '1' THEN

			tclk_dly <= tclk & tclk_dly(0 TO 2);

			IF tclk_dly(0) = '1' THEN
				tx_data_reg	<= tx_data;
			END IF;

			IF init = '1' THEN 
				tclk_dly 	<= (OTHERS => '0');
				tx_data_reg	<= '0';
			END IF;

		END IF;
	END PROCESS get_data_proc;

	d_val <= "001" WHEN tx_data_reg = '0' ELSE "111";  -- 0 -> 1 and 1 -> -1

	d_pos <= resize(shift_right(d_val + d_dly, 1), 2);
	d_neg <= resize(shift_right(d_val - d_dly, 1), 2);

	b_val <= "01" WHEN b_n = '0' ELSE "11";

	d_n_b <= resize(d_neg * b_val, 2);

	enc_proc : PROCESS (clk)
	BEGIN
		IF clk'EVENT AND clk = '1' THEN

			IF tclk_dly(0) = '1' THEN 

				b_n 	<= NOT b_n; 						-- b[n] = (-1)^n
				d_dly 	<= d_val;

			END IF;

			IF tclk_dly(1) = '1' THEN

				d_s1 	<= d_pos;
				d_s2 	<= d_n_b;

			END IF;

			IF init = '1' THEN
				b_n 	<= '0';
				d_dly 	<= "001";
				d_s1 	<= "00";
				d_s2	<= "00";
			END IF;

		END IF;
	END PROCESS enc_proc;


	carrier_mod_proc : PROCESS (clk)
	BEGIN
		IF clk'EVENT AND clk = '1' THEN

			s1 <= resize(d_s1 * signed(carrier_cos_f1), SINUSOID_W);
			s2 <= resize(d_s2 * signed(carrier_cos_f2), SINUSOID_W);

			tx_samples <= std_logic_vector(s1 + s2);

			IF init = '1' THEN
				s1 <= (OTHERS => '0');
				s2 <= (OTHERS => '0');
				tx_samples <= (OTHERS => '0');
			END IF;
		END IF;
	END PROCESS carrier_mod_proc;


	U_tclk_nco : ENTITY work.nco(rtl)
	GENERIC MAP(
		NCO_W 			=> NCO_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> init,
	
		freq_word 		=> freq_word_tclk,
		freq_adjust 	=> std_logic_vector(to_signed(0, NCO_W)),
	
		phase    		=> OPEN,
		rollover_pi2 	=> OPEN,
		rollover_pi 	=> OPEN,
		rollover_3pi2 	=> OPEN,
		rollover_2pi 	=> OPEN,
		tclk_even		=> tclk_even,
		tclk_odd		=> tclk_odd
	);

	U_f1_nco : ENTITY work.nco(rtl)
	GENERIC MAP(
		NCO_W 			=> NCO_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> init,
	
		freq_word 		=> freq_word_f1,
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
		init 			=> init,
	
		phase 			=> carrier_phase_f1(NCO_W -1 DOWNTO NCO_W - PHASE_W),

		sin_out			=> OPEN,
		cos_out			=> carrier_cos_f1
	);

	U_f2_nco : ENTITY work.nco(rtl)
	GENERIC MAP(
		NCO_W 			=> NCO_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> init,
	
		freq_word 		=> freq_word_f2,
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
		init 			=> init,
	
		phase 			=> carrier_phase_f2(NCO_W -1 DOWNTO NCO_W - PHASE_W),

		sin_out			=> OPEN,
		cos_out			=> carrier_cos_f2
	);


END ARCHITECTURE rtl;