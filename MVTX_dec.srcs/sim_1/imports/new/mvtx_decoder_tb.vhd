----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 23.07.2022 15:21:37
-- Design Name: 
-- Module Name: ctpreadout_tb - uut
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.std_logic_misc.all;

use ieee.std_logic_textio.all;
library std;
use std.textio.all;

use std.env.stop;
use std.env.finish;






-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity ctpreadout_tb is
--  Port ( );
end ctpreadout_tb;

architecture tb of ctpreadout_tb is

  constant C_CLK_FREQ   : real := 240.0e6;
  constant C_CLK_PERIOD : time := 1 sec / C_CLK_FREQ;

  signal clk_240       : std_logic := '0';
  signal tick : std_logic := '0';
  signal clk_240_gbt       : std_logic := '0';
  signal tick_gbt : std_logic := '0';
  signal Counter_b   : natural := 0;
   signal Counter_b_gbt   : natural := 0;
  signal tickpipe         : std_logic_vector(6 downto 1);
  signal bcid   : std_logic_vector(11 downto 0) := (others => '0');
  signal Counter_bcid   : std_logic_vector(31 downto 0) := (others => '0');
  signal orbitid   : std_logic_vector(31 downto 0) := (others => '0');
  signal Counter_hb   : natural := 0;
  --signal hb : std_logic := '0';
  signal hb_del4 : std_logic := '0';
  signal tf : std_logic := '0';
  signal tf_ff : std_logic := '0';
  
  signal gbt_rx_clk240_en_s : std_logic_vector (1 to 2) := (others => '0');
  signal gbt_rx_wordclk_s : std_logic_vector (1 to 2) := (others => '0');
  
  signal gbt_rx_data_s : std_logic_vector (84-1 downto 0) := (others => '0');
  
  signal gbt_rx_data_user_s : std_logic_vector (84-1 downto 0) := (others => '0');
  
  signal gbt1_tx_data : std_logic_vector(79 downto 0) := (others => '0');
  
  signal ir_state_machine_codes_s : std_logic_vector(63 downto 0) := (others => '0');
  
  
  file   in_file         : text open read_mode is "C:\Users\jkvapil\Downloads\MVTX_dec\Simulations\testshort.txt";
  file   out_file         : text open write_mode is "C:\Users\jkvapil\Downloads\MVTX_dec\Simulations\testoutput.txt";
  
  signal gbt_din_wr : std_logic := '0';
  
  signal SOR_sent : std_logic := '0';
  
  signal EOR_sent : std_logic := '0';
  
  signal clk_del : std_logic := '0';
  
   signal fileEOF  : std_logic := '0';
  
  signal orbit : std_logic := '0';
  signal rst : std_logic := '0';
  signal start : std_logic := '0';
  
  signal ir_data_s : std_logic_vector(47 downto 0) := (others => '0');
   signal data : std_logic_vector(79 downto 0) := (others => '0');
   signal data_valid : std_logic := '0';
   
       signal s_pixel_coord              : std_logic_vector(18 downto 0):= (others => '0');
	signal s_pixel_ready              :  std_logic  := '0';
  
--alias start is <<signal .UUT.start_ctpreadout : std_logic>>;
  
begin

clk_240 <= not clk_240 after C_CLK_PERIOD/2;
  
p_TickGenerator: process (clk_240) is begin
    if rising_edge(clk_240) then
        tick <= '0';
        Counter_b <= Counter_b + 1;
        if Counter_b = 5 then
            tick <= '1';
            Counter_b <= 0;
        end if;
    end if;
end process;

tickpipe <= tickpipe(5 downto 1) & tick when rising_edge(clk_240);

main :process begin
    rst <= '1';
    wait for 1000 ns;
    rst <= '0';
    start <= '1';
    wait for 10000 ns;
end process main;

-- ==================================
-- Reading RU data from file
-- ==================================
p_file_read:process(clk_240)
    variable v_line_in : line;
    variable v_data  : std_logic_vector(79 downto 0);
    variable valid : boolean;
begin
    if rising_edge(clk_240) then
    if (start = '1') then
        if( not endfile(in_file)) then
            readline(in_file,v_line_in);
            --report "v_line_in: " & v_line_in.all;
            hread(v_line_in, v_data,valid);   
        else
            report "endfile";
            valid := FALSE;
    --        stop;
        end if;
    end if;
    end if;
    data<=v_data;
    --data_valid<='1' when valid = TRUE else '0';
    if(valid = TRUE) then
           data_valid<='1';
        else
           data_valid<='0';
        end if;
end process;


-- ==================================
-- Saving to TXT
-- ==================================
p_file_write:process(clk_240)
       variable v_line_out : line;
begin
    if rising_edge(clk_240) then
        if(s_pixel_ready = '1') then
	        write(v_line_out, to_hex_string(s_pixel_coord(18 downto 9)));
	        write(v_line_out,string'("/"));
	        write(v_line_out, to_hex_string(s_pixel_coord(8 downto 0)));
            writeline(out_file,v_line_out);
        end if;
    end if;
end process;

UUT: entity work.decoder_state_machine
    port map (
    --------------------------------------------------------------------------------
    -- RESETs
    --------------------------------------------------------------------------------
   -- ipb_rst                    => '0',
   -- rst_ctpreadout_i           => "00000",
	--------------------------------------------------------------------------------
    -- TIMING
    --------------------------------------------------------------------------------
    clk_i                => clk_240,
    rst_i => rst,
    pixel_coord_o  => s_pixel_coord,
	pixel_ready_o => s_pixel_ready,
    data_i		         => data,
	data_valid_i         =>data_valid
    
    
    
    --tick_bc                   => tick,

       
    );




--UUT: entity work.ctpreadout
--    port map (
--    --------------------------------------------------------------------------------
--    -- RESETs
--    --------------------------------------------------------------------------------
--    ipb_rst                    => '0',
--    rst_ctpreadout_i           => "00000",
--	--------------------------------------------------------------------------------
--    -- TIMING
--    --------------------------------------------------------------------------------
--    clk_bc_240                => clk_240,
--    tick_bc                   => tick,
--    tf_del2                   => tf,
--   -- hb                        => hb,
--    hb_del4                   => hb_del4,
--    --------------------------------------------------------------------------------
--    -- GBT in
--    --------------------------------------------------------------------------------
--    gbt_rx_clk240_en_i             => gbt_rx_clk240_en_s,--: in std_logic_vector (1 to 2);
--    gbt_rx_data_i                  => gbt_rx_data_s,--: in gbt_reg84_A(1 to 2); 
--    gbt_rx_wordclk_i               =>gbt_rx_wordclk_s,--: in std_logic_vector (1 to 2);   -- Comment. Tick, sync w.r.t GBT Clock Domain
--    gbtRxReady_from_gbtExmplDsgn_i => tick_gbt&'0',--: in std_logic_vector (1 to 2); 
--    rxIsData_from_gbtExmplDsgn_i => '0'&'0',
--     --------------------------------------------------------------------------------
--    -- GBT out
--    --------------------------------------------------------------------------------
--    gbt1_rx_data_o                 => open,--: out std_logic_vector(85 downto 0);
--    gbt2_rx_data_o                 => open,--: out std_logic_vector(85 downto 0);
--    gbt1_tx_data_o                 => gbt1_tx_data,--: out std_logic_vector (79 downto 0);
--    gbt1_txIsDataSel_o             => open,--: out std_logic;
--    gbt2_tx_data_o                 => open,--: out std_logic_vector (79 downto 0);
--    gbt2_txIsDataSel_o             => open,--: out std_logic;
--    --------------------------------------------------------------------------------
--    -- Input Data		
--    --------------------------------------------------------------------------------
--    bcid                         => bcid,
--    orbitid                      => orbitid,
--    d_i_ir                       => ir_data_s,--: in  std_logic_vector (47 downto 0);    
--    d_i_tcr                      => x"0123456789ABCDEF",--: in  std_logic_vector (63 downto 0); 
--    oredXOX                      => hb_del4, --: in  std_logic;
--    --------------------------------------------------------------------------------   
--    -- Control
--    --------------------------------------------------------------------------------
--    ctpreadout_ctrl_i => x"00",         --   : in ipb_reg_v(7 downto 0);
--    --------------------------------------------------------------------------------
--    -- monitoring
--    --------------------------------------------------------------------------------
--    ctpreadout_stat_o =>  open,     -- : out ipb_reg_v(7 downto 0);
--    --------------------------------------------------------------------------------
--    -- State machine coders 
--    --------------------------------------------------------------------------------
--    ctpreadout_cnts_o =>  ir_state_machine_codes_s,   -- : out std_logic_vector (63 downto 0);
--    --------------------------------------------------------------------------------
--    -- Miscellaneous
--    --------------------------------------------------------------------------------
--    sn                        => x"AB"--: in    std_logic_vector (7 downto 0)
       
--    );


end tb;
