--------------------------------------------------------------------------------
-- Title      : MVTX data decoder
-- Project    : FastML
-------------------------------------------------------------------------------
-- File       : decoder_state_machine.vhd
-- Author     : Jakub Kvapil (jakub.kvapil@cern.ch)
-------------------------------------------------------------------------------
-- Description: Reading standard RDH messages
-- 
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package decoder_state_machine_type is
    type t_pixel_coord is array (0 to 8) of std_logic_vector(18 downto 0);
end package decoder_state_machine_type;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;
Library xil_defaultlib;
use xil_defaultlib.ALL;
use work.decoder_state_machine_type.all;

entity decoder_state_machine is
    --FEEID
    generic (
    device : std_logic_vector(3 downto 0) := "1001"
    );
  port (
    --------------------------------------------------------------------------------
    -- CLK and RESET
    --------------------------------------------------------------------------------
    clk_i                     : in  std_logic;
    rst_i                     : in  std_logic;
	------------------------------------------------------
	-- Data Control
	------------------------------------------------------
	data_i		              : in  std_logic_vector(79 downto 0);
	data_valid_i              : in std_logic;
    pixel_coord_o             : out t_pixel_coord;
    pixel_valid_o              : out std_logic_vector(8 downto 0);
    pixel_read_i              : in std_logic_vector(8 downto 0);
	decoder_mon_o              : out std_logic_vector(55 downto 0)
    --------------------------------------------------------------------------------
    -- MONITORING
    --------------------------------------------------------------------------------
   	--state_machine_mon_o : out std_logic_vector(10 downto 0);

    );
end decoder_state_machine;

architecture rtl of decoder_state_machine is
  -- CONSTANT
  constant c_RDH               : std_logic_vector(7 downto 0)  := x"00";
  constant c_IHW               : std_logic_vector(7 downto 0)  := x"e0";
  constant c_TDH               : std_logic_vector(7 downto 0)  := x"e8";
  constant c_TDT               : std_logic_vector(7 downto 0)  := x"f0";
  constant c_DDW               : std_logic_vector(7 downto 0)  := x"e4";
  constant c_CDW               : std_logic_vector(7 downto 0)  := x"f8";
  constant c_IDLE              : std_logic_vector(7 downto 0)  := x"ff";
  
  signal c_HEADER_SIZE         : std_logic_vector(7 downto 0)  := x"20";
  signal c_HEADER_VERSION      : std_logic_vector(7 downto 0)  := x"08";
  
  
  signal s_data             : std_logic_vector(79 downto 0);
  
  signal s_detector_field      : std_logic_vector(31 downto 0);
  signal s_source_id           : std_logic_vector(7 downto 0);
  signal s_feeid               : std_logic_vector(15 downto 0);
  signal s_rdh_bco             : std_logic_vector(39 downto 0);
  signal s_rdh_lhc             : std_logic_vector(11 downto 0);
  signal s_rdh_ttype           : std_logic_vector(31 downto 0);
  
  signal s_tdh_bco             : std_logic_vector(39 downto 0);
  signal s_tdh_lhc             : std_logic_vector(11 downto 0);
  
  signal s_tdh_last_bco        : std_logic_vector(39 downto 0) := (others => '0');
  signal s_tdh_last_lhc        : std_logic_vector(11 downto 0) := (others => '0');
  
  type t_chip_array is array (0 to 8) of std_logic_vector(71 downto 0);
  signal s_chip_data_fifo_in: t_chip_array;
  signal s_chip_data_fifo_out: t_chip_array;
  
  signal s_chip_data_valid      : std_logic_vector(8 downto 0);
  signal s_chip_data_fifo_wr      : std_logic_vector(8 downto 0);
  --signal s_chip_data_fifo_wr      : std_logic_vector(8 downto 0);
  signal s_chip_data_fifo_empty      : std_logic_vector(8 downto 0);
   
  signal rd_en_s : std_logic_vector(8 downto 0) := (others => '0');
  signal fifo_rst_s : std_logic := '0';
    
  signal s_chip_data_empty      : std_logic_vector(8 downto 0);
    
  signal s_chip_fifo_1_active      : std_logic := '0';
  signal s_chip_fifo_2_active      : std_logic := '0';
    
  signal s_chip_fifo_event_error      : std_logic := '0';
    
  signal s_chip_fifo_switch      : std_logic := '0'; --0 1sts et, 1 second set
    
 -- type t_pixel_coord is array (0 to 8) of std_logic_vector(18 downto 0);
  signal s_pixel_coord: t_pixel_coord;
  
  --   signal s_pixel_coord              : std_logic_vector(18 downto 0):= (others => '0');
  signal s_pixel_ready              : std_logic_vector(8 downto 0) := (others => '0');
  
  signal s_pixel_valid              : std_logic_vector(8 downto 0) := (others => '0');
  --signal s_pixel_read_in              : std_logic_vector(8 downto 0) := (others => '0');
    
  signal s_pixel_read              : std_logic_vector(8 downto 0) := (others => '0');
  signal s_pixel_coord_out: t_pixel_coord;  
    
  signal s_mon_RDH            : std_logic_vector(19 downto 0) := (others => '0');
  
  signal s_alpide_mon  : std_logic_vector(35 downto 0) := (others => '0');
        
    
     
  -- SM
  
  type t_states is (
    IDLE,
    RDH_WORD0,
    RDH_WORD1,
    RDH_WORD2,
    IHW,
    TDH,
    TDT,
    DDW,
    CDW,
    PAYLOAD,
    IB_DATA
    );
  signal s_cs           : t_states;
  signal s_ps           : t_states;
  
begin

fifo_rst_s <= rst_i;

p_read_data : process(clk_i)
begin
    if rising_edge(clk_i) then
        s_ps <= s_cs;
        s_mon_RDH <= (others => '0');
        s_chip_data_fifo_wr <= (others => '0');
        s_chip_data_fifo_in <= (others => (others => '0'));     
        if data_valid_i = '1' then
            case data_i(79 downto 72) is
                when c_RDH =>
                    s_mon_RDH(0) <= '1';
                    if data_i(15 downto 0) = c_HEADER_SIZE & c_HEADER_VERSION then
                        s_cs <= RDH_WORD0; 
                        s_detector_field <= data_i(71 downto 40);     
                        s_source_id      <= data_i(39 downto 32); 
                        s_feeid          <= data_i(31 downto 16);
                        s_mon_RDH(1) <= '1';     
                    elsif s_cs = RDH_WORD0 then
                        s_cs <= RDH_WORD1;        
                        s_rdh_bco        <= data_i(71 downto 32);     
                        s_rdh_lhc        <= data_i(11 downto 0);  
                        s_mon_RDH(2) <= '1';          
                    elsif s_cs = RDH_WORD1 then
                        s_cs <= RDH_WORD2; 
                        s_rdh_ttype      <= data_i(31 downto 0);   
                        s_mon_RDH(3) <= '1';               
                    end if;                  
                when c_IHW =>
                    s_cs <= IHW;  
                    s_mon_RDH(4) <= '1';               
                when c_TDH =>
                    s_cs <= TDH;
                    s_tdh_bco        <= data_i(71 downto 32);     
                    s_tdh_lhc        <= data_i(27 downto 16);
                    s_mon_RDH(5) <= '1'; 
                    if (data_i(71 downto 32) /= s_tdh_last_bco) and s_feeid(3 downto 0) = "0011" then
                        s_tdh_last_bco <=  data_i(71 downto 32);   
                        --terminate stream
                        s_chip_data_fifo_wr <= (others => '1');
                        s_chip_data_fifo_in <= (others => (others => '1'));                
                    end if;
                when c_TDT =>
                    s_cs <= TDT;  
                    s_mon_RDH(6) <= '1';          
                when c_DDW =>
                    s_cs <= DDW;
                    s_mon_RDH(7) <= '1';                
                when c_CDW =>
                    s_cs <= CDW;   
                    s_mon_RDH(8) <= '1';            
                when c_IDLE =>
                    s_cs <= IDLE; 
                    s_mon_RDH(9) <= '1';                   
                when others => --must be payload
                    --filtering curent file to have only one stave 
                    if s_feeid(3 downto 0) = "0011" then                    
                        if data_i(79 downto 77) = "001" then             
                            s_cs <= IB_DATA;
                            s_mon_RDH(10) <= '1'; 
                            case data_i(75 downto 72) is
                                when x"0" =>
                                    s_chip_data_fifo_in(0) <= data_i(71 downto 0);
                                    s_chip_data_fifo_wr(0) <= '1';
                                    s_mon_RDH(11) <= '1';
                                when x"1" =>
                                    s_chip_data_fifo_in(1) <= data_i(71 downto 0);
                                    s_chip_data_fifo_wr(1) <= '1';
                                    s_mon_RDH(12) <= '1';
                                when x"2" =>
                                    s_chip_data_fifo_in(2) <= data_i(71 downto 0);
                                    s_chip_data_fifo_wr(2) <= '1';
                                    s_mon_RDH(13) <= '1';
                                when x"3" =>
                                    s_chip_data_fifo_in(3) <= data_i(71 downto 0);
                                    s_chip_data_fifo_wr(3) <= '1';
                                    s_mon_RDH(14) <= '1';
                                when x"4" =>
                                    s_chip_data_fifo_in(4) <= data_i(71 downto 0);
                                    s_chip_data_fifo_wr(4) <= '1';
                                    s_mon_RDH(15) <= '1';
                                when x"5" =>
                                    s_chip_data_fifo_in(5) <= data_i(71 downto 0);
                                    s_chip_data_fifo_wr(5) <= '1';
                                    s_mon_RDH(16) <= '1';
                                when x"6" =>
                                    s_chip_data_fifo_in(6) <= data_i(71 downto 0);
                                    s_chip_data_fifo_wr(6) <= '1';
                                    s_mon_RDH(17) <= '1';
                                when x"7" =>
                                    s_chip_data_fifo_in(7) <= data_i(71 downto 0);
                                    s_chip_data_fifo_wr(7) <= '1';
                                    s_mon_RDH(18) <= '1';
                                when x"8" =>
                                    s_chip_data_fifo_in(8) <= data_i(71 downto 0);
                                    s_chip_data_fifo_wr(8) <= '1';
                                    s_mon_RDH(19) <= '1';
                                when others =>
                                    s_chip_data_fifo_wr <= (others => '0');        
                            end case;
                        end if;
                    end if;
            end case;
        end if;
    end if;
end process p_read_data;

gen_chips_fifo : for m in 0 to 8 generate
begin
chip_fifo: entity work.fifo_chipdata_72x64
    PORT MAP (
        CLK => clk_i,
        VALID => s_chip_data_valid(m),
        SRST => fifo_rst_s,
        wr_rst_busy => open,
        rd_rst_busy => open,
        WR_EN => s_chip_data_fifo_wr(m),
        RD_EN => rd_en_s(m),
        DIN => s_chip_data_fifo_in(m),--(m),
        DOUT => s_chip_data_fifo_out(m),
        FULL => open,
        EMPTY => s_chip_data_fifo_empty(m)    
      );
end generate;  

gen_alpide_decoder : for m in 0 to 8 generate
begin
alpide_dec: entity work.alpide_decoder
    PORT MAP (
        clk_i => clk_i,
        rst_i => '0',
        data_i => s_chip_data_fifo_out(m),
        pixel_coord_o  => s_pixel_coord(m),
	    pixel_ready_o => s_pixel_ready(m),
	    fifo_valid_i => s_chip_data_valid(m),
	    fifo_empty_i => s_chip_data_fifo_empty(m),
	    fifo_read_o => rd_en_s(m),
	    alpide_mon_o => s_alpide_mon((4*m + 3) downto (4*m))
      );
end generate;  

gen_pixel_fifo_1 : for m in 0 to 8 generate
begin
pixel_fifo: entity work.fifo_hitdata_19x128
    PORT MAP (
        CLK => clk_i,
        VALID => s_pixel_valid(m),
        SRST => fifo_rst_s,
        wr_rst_busy => open,
        rd_rst_busy => open,
        WR_EN => s_pixel_ready(m),
        RD_EN => pixel_read_i(m),
        DIN => s_pixel_coord(m),--(m),
        DOUT => s_pixel_coord_out(m),
        FULL => open,
        EMPTY => open    
      );
end generate; 

pixel_coord_o <=  s_pixel_coord_out;
pixel_valid_o <= s_pixel_valid;
decoder_mon_o <= s_alpide_mon & s_mon_RDH;

end rtl;