

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

		tclk 				: OUT std_logic;

		mod_freq_word 		: IN  std_logic_vector(NCO_W -1 DOWNTO 0);
		car_freq_word	 	: IN  std_logic_vector(NCO_W -1 DOWNTO 0);

		tx_data 			: IN  std_logic_vector(1 DOWNTO 0);
		tx_req 				: OUT std_logic;

		tx_samples	 		: OUT std_logic_vector(SAMPLE_W -1 DOWNTO 0)
	);
END ENTITY msk_modulator;

ARCHITECTURE rtl OF msk_modulator IS 

	SIGNAL mod_phase 		: std_logic_vector(NCO_W -1 DOWNTO 0);
	SIGNAL rollover_pi2 	: std_logic;
	SIGNAL rollover_pi 		: std_logic;
	SIGNAL rollover_3pi2 	: std_logic;
	SIGNAL rollover_2pi 	: std_logic;
	SIGNAL tclk_even		: std_logic;
	SIGNAL tclk_odd 		: std_logic;

	SIGNAL car_phase 		: std_logic_vector(NCO_W -1 DOWNTO 0);

	SIGNAL mod_sin	 		: std_logic_vector(SINUSOID_W -1 DOWNTO 0);
	SIGNAL mod_cos	 		: std_logic_vector(SINUSOID_W -1 DOWNTO 0);
	SIGNAL mod_sin_d 		: std_logic_vector(SINUSOID_W -1 DOWNTO 0);
	SIGNAL mod_cos_d 		: std_logic_vector(SINUSOID_W -1 DOWNTO 0);

	SIGNAL carrier_sin	 	: std_logic_vector(SINUSOID_W -1 DOWNTO 0);
	SIGNAL carrier_cos	 	: std_logic_vector(SINUSOID_W -1 DOWNTO 0);

	SIGNAL tx_req_d 		: std_logic;

	SIGNAL tx_data_reg		: std_logic_vector(1 DOWNTO 0);

	SIGNAL tx_enc_even		: std_logic;
	SIGNAL tx_enc_odd 		: std_logic;

	SIGNAL tx_enc_odd_delay	: std_logic;

	SIGNAL tx_data_enc		: std_logic_vector(1 DOWNTO 0);

	SIGNAL tx_symbol_I		: std_logic_vector(SINUSOID_W -1 DOWNTO 0);
	SIGNAL tx_symbol_Q		: std_logic_vector(SINUSOID_W -1 DOWNTO 0);

	SIGNAL tx_sample_I 		: signed(2*SINUSOID_W -1 DOWNTO 0);
	SIGNAL tx_sample_Q 		: signed(2*SINUSOID_W -1 DOWNTO 0);

	--TYPE diff_enc_lut_type IS ARRAY(0 TO 7) OF std_logic_vector(1 DOWNTO 0);

	--CONSTANT diff_enc_lut 	: diff_enc_lut_type := (
	--								0 => "0100",			--  1  1  1 =>  1  0
	--								1 => "0001",			--  1  1 -1 =>  0  1
	--								2 => "0011",			--  1 -1  1 =>  0 -1
	--								3 => "1100",			--  1 -1 -1 => -1  0
	--								4 => "0100",			-- -1  1  1 =>  1  0
	--								5 => "0011",			-- -1  1 -1 =>  0 -1
	--								6 => "0001",			-- -1 -1  1 =>  0  1
	--								7 => "1100" ); 			-- -1 -1 -1 => -1  0

BEGIN

	tx_req 	<= tclk_even;

	tclk 	<= tclk_even OR tclk_odd;

	get_data_proc : PROCESS (clk)
	BEGIN
		IF clk'EVENT AND clk = '1' THEN

			tx_req_d <= tclk_even;

			IF tx_req_d = '1' THEN
				tx_data_reg	<= tx_data;
			END IF;

			IF init = '1' THEN 
				tx_req_d 	<= '0';
				tx_data_reg	<= "00";
			END IF;

		END IF;
	END PROCESS get_data_proc;

	-- Differential Encoder
	--
	-- See Section 5.8 Alternative scheme–differential encoder of 
	-- 		_Wireless Communications: Principles, Theory and Methodology_, Zhang
	--
	--	β_n = ⍺_n * β_(n-1) where ⍺_n is the input data sequence and ⍺ ∈ {-1,1}
	--
	--	A single-bit number can be treated as signed where:
	--	
	--	1 -> -1
	--  0 ->  1
	--
	-- tx_enc_even <= β_(2n)
	-- tx_enc_odd  <= β_(2n+1)
	--

	diff_enc_proc : PROCESS (clk)
	BEGIN
		IF clk'EVENT AND clk = '1' THEN

			IF tclk_even = '1' THEN		-- only process on symbol boundaries

				tx_enc_even  	<= tx_data_reg(0) XOR tx_enc_odd;
				tx_enc_odd  	<= tx_data_reg(1) XOR tx_data_reg(0) XOR tx_enc_odd;

			END IF;

			IF init = '1' THEN 
				tx_enc_even 	<= '1';
				tx_enc_odd  	<= '1';
			END IF;

		END IF;
	END PROCESS diff_enc_proc;

	tx_data_enc <= tx_enc_odd_delay & tx_enc_even;

	shape_proc : PROCESS (clk)
	BEGIN
		IF clk'EVENT AND clk = '1' THEN

			-- Delay sin/cos by 1 clock to align with tx_I/Q
			mod_sin_d <= mod_sin;				
			mod_cos_d <= mod_cos;

			-- Offset odd channel by 1/2 symbol period (T)
			IF tclk_odd = '1' THEN
				tx_enc_odd_delay <= tx_enc_odd;
			END IF;

			-- Tx_I/Tx_Q are a single bit, but treated as signed. 0 => 1, 1 => -1

			-- The multiplies are implemented as muxes because we are multiplying by
			-- either 1 or -1. Perhaps the toolchain will optimize to muxes, but
			-- we code as muxes to ensure the best result.

			-- tx_symbol_I <= tx_I * mod_cos
			IF tx_enc_even = '1' THEN
				tx_symbol_I <= std_logic_vector(unsigned(NOT(mod_cos_d)) + 1);		-- multiply by -1
			ELSE
				tx_symbol_I <= mod_cos_d;
			END IF;

			-- tx_symbol_Q <= tx_Q * mod_sin
			IF tx_enc_odd_delay = '1' THEN
				tx_symbol_Q <= std_logic_vector(unsigned(NOT(mod_sin_d)) + 1); 		-- multiply by -1
			ELSE
				tx_symbol_Q <= mod_sin_d;
			END IF;

		END IF;
	END PROCESS shape_proc;


	mod_proc : PROCESS (clk)
	BEGIN
		IF clk'EVENT AND clk = '1' THEN

			tx_sample_I <= signed(tx_symbol_I) * signed(carrier_cos);
			tx_sample_Q <= signed(tx_symbol_Q) * signed(carrier_sin);

			tx_samples  <= std_logic_vector(resize(shift_right(tx_sample_I + tx_sample_Q, SINUSOID_W), SAMPLE_W));

			IF init = '1' THEN
				tx_samples  <= (OTHERS => '0');
				tx_sample_I <= (OTHERS => '0');
				tx_sample_Q <= (OTHERS => '0');
			END IF;

		END IF;
	END PROCESS mod_proc;


	U_mod_nco : ENTITY work.nco(rtl)
	GENERIC MAP(
		NCO_W 			=> NCO_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> init,
	
		freq_word 		=> mod_freq_word,
		freq_adjust 	=> std_logic_vector(to_signed(0, NCO_W)),
	
		phase    		=> mod_phase,
		rollover_pi2 	=> rollover_pi2,
		rollover_pi 	=> rollover_pi,
		rollover_3pi2 	=> rollover_3pi2,
		rollover_2pi 	=> rollover_2pi,
		tclk_even		=> tclk_even,
		tclk_odd		=> tclk_odd
	);

	U_mod_sin_cos_lut : ENTITY work.sin_cos_lut(lut_based)
	GENERIC MAP(
		PHASE_W 		=> PHASE_W,
		PHASES 			=> 2**PHASE_W,
		SINUSOID_W 		=> SINUSOID_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> init,
	
		phase 			=> mod_phase(NCO_W -1 DOWNTO NCO_W - PHASE_W),

		sin_out			=> mod_sin,
		cos_out			=> mod_cos
	);


	U_carrier_nco : ENTITY work.nco(rtl)
	GENERIC MAP(
		NCO_W 			=> NCO_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> init,
	
		freq_word 		=> car_freq_word,
		freq_adjust 	=> std_logic_vector(to_signed(0, NCO_W)),
	
		phase    		=> car_phase,
		rollover_pi2 	=> OPEN,
		rollover_pi 	=> OPEN,
		rollover_3pi2 	=> OPEN,
		rollover_2pi 	=> OPEN,
		tclk_even		=> OPEN,
		tclk_odd		=> OPEN
	);

	U_carrier_sin_cos_lut : ENTITY work.sin_cos_lut(lut_based)
	GENERIC MAP(
		PHASE_W 		=> PHASE_W,
		PHASES 			=> 2**PHASE_W,
		SINUSOID_W 		=> SINUSOID_W
	)
	PORT MAP(
		clk 			=> clk,
		init 			=> init,
	
		phase 			=> car_phase(NCO_W -1 DOWNTO NCO_W - PHASE_W),

		sin_out			=> carrier_sin,
		cos_out			=> carrier_cos
	);


END ARCHITECTURE rtl;